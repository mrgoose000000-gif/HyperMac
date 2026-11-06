import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import Combine

// MARK: - Screenshot Tool & Stroke Models

public enum ScreenshotTool: String, CaseIterable, Sendable {
    case move       // Move selection box
    case pen        // Freehand ink
    case arrow      // Directional pointer arrow
    case rect       // Rectangle outline
    case marker     // Semi-transparent highlighter
}

public struct DrawnStroke: Identifiable, Sendable {
    public let id: UUID
    public var tool: ScreenshotTool
    public var points: [CGPoint] // points relative to the screen frame
    public var colorHex: String
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), tool: ScreenshotTool, points: [CGPoint], colorHex: String, lineWidth: CGFloat) {
        self.id = id
        self.tool = tool
        self.points = points
        self.colorHex = colorHex
        self.lineWidth = lineWidth
    }

    public var color: Color {
        Color(hex: colorHex)
    }

    public var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }
}

public enum ResizeHandle: CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case midLeft, midRight
    case bottomLeft, bottomCenter, bottomRight
}

// MARK: - Dynamic CoreGraphics Loader for Instant Screen Capture

private typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

private let cgCaptureSym: CGWindowListCreateImageFunc? = {
    if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
       let sym = dlsym(handle, "CGWindowListCreateImage") {
        return unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
    }
    return nil
}()

// MARK: - Screenshot Manager (LightShot Engine)

@MainActor
public class ScreenshotManager: ObservableObject {
    public static let shared = ScreenshotManager()

    // Configuration
    @Published public var isScreenshotEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isScreenshotEnabled, forKey: "screenshot_enabled")
            gIsScreenshotEnabled = isScreenshotEnabled
        }
    }

    // Active Capture State
    @Published public var isActive: Bool = false
    @Published public var screenImage: CGImage? = nil
    @Published public var screenNSImage: NSImage? = nil
    @Published public var screenFrame: NSRect = .zero
    @Published public var scaleFactor: CGFloat = 2.0

    // Selection Box (in screen-local coordinates 0...width, 0...height)
    @Published public var selectionRect: CGRect = .zero
    @Published public var hasSelection: Bool = false

    // Annotation Tools & Colors
    @Published public var currentTool: ScreenshotTool = .pen
    @Published public var selectedColorHex: String = "#FF3B30" // Default Red
    @Published public var strokes: [DrawnStroke] = []
    @Published public var activeStroke: DrawnStroke? = nil
    @Published public var isColorPaletteExpanded: Bool = false

    // Drag Interaction Tracking
    @Published public var activeHandle: ResizeHandle? = nil
    @Published public var dragStartPoint: CGPoint = .zero
    @Published public var dragStartRect: CGRect = .zero
    @Published public var isDraggingSelection: Bool = false

    // Notifications / Toasts
    @Published public var toastMessage: String? = nil

    // Palette Colors (LightShot style)
    public let availableColors: [String] = [
        "#FF3B30", // Đỏ (Red - Default)
        "#FF9500", // Cam (Orange)
        "#FFCC00", // Vàng (Yellow)
        "#34C759", // Xanh lá (Green)
        "#007AFF", // Xanh dương (Blue)
        "#AF52DE", // Tím (Purple)
        "#FFFFFF", // Trắng (White)
        "#000000"  // Đen (Black)
    ]

    private var overlayPanel: NSPanel?

    private init() {
        if UserDefaults.standard.object(forKey: "screenshot_enabled") != nil {
            self.isScreenshotEnabled = UserDefaults.standard.bool(forKey: "screenshot_enabled")
        } else {
            self.isScreenshotEnabled = true
        }
        gIsScreenshotEnabled = self.isScreenshotEnabled
    }

    // MARK: - Start Snipping / Freeze Screen (LightShot Style)

    public func startCapture() {
        guard isScreenshotEnabled else { return }
        guard !isActive else { return }

        // Check Screen Recording Permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            PermissionsManager.shared.openScreenCaptureSettings()
            return
        }

        // 1. Identify screen under mouse cursor
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let frame = targetScreen.frame
        self.screenFrame = frame

        // 2. Capture synchronous instant high-res snapshot of target screen
        guard let capturedImage = captureScreenImage(screen: targetScreen) else {
            appLog("⚠️ ScreenshotManager: Failed to capture screen image.")
            return
        }

        self.screenImage = capturedImage
        self.scaleFactor = CGFloat(capturedImage.width) / frame.width
        let nsImg = NSImage(cgImage: capturedImage, size: frame.size)
        self.screenNSImage = nsImg

        // Reset state
        self.selectionRect = .zero
        self.hasSelection = false
        self.strokes = []
        self.activeStroke = nil
        self.currentTool = .pen
        self.selectedColorHex = "#FF3B30"
        self.isColorPaletteExpanded = false
        self.toastMessage = nil

        // 3. Create or update full-screen borderless overlay panel
        createOrUpdateOverlayPanel(on: targetScreen)

        self.isActive = true
        gIsScreenshotActive = true
    }

    // MARK: - Capture Screen CGImage

    private func captureScreenImage(screen: NSScreen) -> CGImage? {
        let primaryH = NSScreen.screens[0].frame.height
        let f = screen.frame
        let cgRect = CGRect(x: f.origin.x, y: primaryH - (f.origin.y + f.height), width: f.width, height: f.height)

        if let fn = cgCaptureSym, let unmanaged = fn(cgRect, 1, 0, 0) {
            return unmanaged.takeRetainedValue()
        }

        // Fallback: screencapture CLI
        let tempPath = "/tmp/hypermac_screenshot_\(UUID().uuidString).png"
        let res = shell("screencapture -x -C -R \(Int(cgRect.origin.x)),\(Int(cgRect.origin.y)),\(Int(cgRect.width)),\(Int(cgRect.height)) \"\(tempPath)\"")
        if res.exitCode == 0, let image = NSImage(contentsOfFile: tempPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try? FileManager.default.removeItem(atPath: tempPath)
            return image
        }

        return nil
    }

    // MARK: - Overlay Window Presentation

    private func createOrUpdateOverlayPanel(on screen: NSScreen) {
        if overlayPanel == nil {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovableByWindowBackground = false
            panel.acceptsMouseMovedEvents = true

            let hostingView = NSHostingView(rootView: ScreenshotOverlayView(manager: self))
            panel.contentView = hostingView
            self.overlayPanel = panel
        }

        guard let panel = overlayPanel else { return }
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Cancel Capture

    public func cancelCapture() {
        overlayPanel?.orderOut(nil)
        self.isActive = false
        gIsScreenshotActive = false
        self.screenImage = nil
        self.screenNSImage = nil
        self.strokes = []
        self.activeStroke = nil
        self.selectionRect = .zero
        self.hasSelection = false
    }

    // MARK: - Stroke Management

    public func undoLastStroke() {
        if !strokes.isEmpty {
            strokes.removeLast()
        }
    }

    public func clearAllStrokes() {
        strokes.removeAll()
    }

    // MARK: - High-Res Composite Render Engine (Maximum Retina Quality)

    public func renderCompositeImage() -> CGImage? {
        guard let baseCG = screenImage else { return nil }
        guard selectionRect.width >= 5 && selectionRect.height >= 5 else { return nil }

        let scale = self.scaleFactor
        let pixelCropRect = CGRect(
            x: round(selectionRect.origin.x * scale),
            y: round(selectionRect.origin.y * scale),
            width: round(selectionRect.width * scale),
            height: round(selectionRect.height * scale)
        )

        let targetW = Int(pixelCropRect.width)
        let targetH = Int(pixelCropRect.height)
        guard targetW > 0 && targetH > 0 else { return nil }

        guard let colorSpace = baseCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 1. Draw base cropped screenshot
        if let croppedBase = baseCG.cropping(to: pixelCropRect) {
            ctx.draw(croppedBase, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        }

        // 2. Setup context to draw annotations in top-left coordinate system
        ctx.saveGState()
        // Flip to top-left coordinates to match SwiftUI screen layout
        ctx.translateBy(x: 0, y: CGFloat(targetH))
        ctx.scaleBy(x: 1.0, y: -1.0)

        // Scale by Retina multiplier and offset by selection origin
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -selectionRect.origin.x, y: -selectionRect.origin.y)

        // Render each stroke
        for stroke in strokes {
            drawStroke(stroke, in: ctx)
        }

        ctx.restoreGState()

        return ctx.makeImage()
    }

    private func drawStroke(_ stroke: DrawnStroke, in ctx: CGContext) {
        guard !stroke.points.isEmpty else { return }

        ctx.saveGState()
        ctx.setStrokeColor(stroke.nsColor.cgColor)
        ctx.setFillColor(stroke.nsColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(stroke.lineWidth)

        if stroke.tool == .marker {
            ctx.setAlpha(0.38)
        } else {
            ctx.setAlpha(1.0)
        }

        switch stroke.tool {
        case .pen, .marker:
            ctx.beginPath()
            ctx.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() {
                ctx.addLine(to: pt)
            }
            ctx.strokePath()

        case .arrow:
            guard stroke.points.count >= 2 else { break }
            let start = stroke.points[0]
            let end = stroke.points[stroke.points.count - 1]

            // Main arrow line
            ctx.beginPath()
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

            // Arrow head wings
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = max(12, stroke.lineWidth * 3.5)
            let arrowAngle: CGFloat = .pi / 6

            let p1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let p2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )

            ctx.beginPath()
            ctx.move(to: p1)
            ctx.addLine(to: end)
            ctx.addLine(to: p2)
            ctx.strokePath()

        case .rect:
            guard stroke.points.count >= 2 else { break }
            let p1 = stroke.points[0]
            let p2 = stroke.points[stroke.points.count - 1]
            let rect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: abs(p2.x - p1.x),
                height: abs(p2.y - p1.y)
            )
            ctx.stroke(rect, width: stroke.lineWidth)

        case .move:
            break
        }

        ctx.restoreGState()
    }

    // MARK: - Copy Action (⌘C / LightShot Style)

    public func copyToClipboard() {
        guard let finalCG = renderCompositeImage() else {
            cancelCapture()
            return
        }

        let rep = NSBitmapImageRep(cgImage: finalCG)
        rep.size = NSSize(width: selectionRect.width, height: selectionRect.height) // High DPI metadata

        let pngData = rep.representation(using: .png, properties: [:])
        let tiffData = rep.representation(using: .tiff, properties: [:])

        let pb = NSPasteboard.general
        pb.clearContents()
        if let pngData = pngData {
            pb.setData(pngData, forType: .png)
        }
        if let tiffData = tiffData {
            pb.setData(tiffData, forType: .tiff)
        }

        // Play feedback sound
        NSSound(named: "Glass")?.play()

        // Close overlay immediately
        cancelCapture()
    }

    // MARK: - Save Action (⌘V / ⌘S -> Downloads/Screenshots)

    public func saveToDownloads() {
        guard let finalCG = renderCompositeImage() else {
            cancelCapture()
            return
        }

        let rep = NSBitmapImageRep(cgImage: finalCG)
        rep.size = NSSize(width: selectionRect.width, height: selectionRect.height)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            cancelCapture()
            return
        }

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let screenshotsDir = downloadsDir.appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot_\(timestamp).png"
        let fileURL = screenshotsDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL, options: .atomic)
            // Also copy to clipboard so user has both
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(pngData, forType: .png)
            pb.writeObjects([fileURL as NSURL])

            NSSound(named: "Glass")?.play()
            appLog("📸 Screenshot saved to \(fileURL.path)")
        } catch {
            appLog("❌ Error saving screenshot: \(error)")
        }

        cancelCapture()
    }
}

// MARK: - Hex Color Helper for AppKit & SwiftUI

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: Double
        if clean.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 1.0; g = 0.23; b = 0.19
        }
        self.init(red: r, green: g, blue: b)
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else { return nil }
        if clean.count == 6 {
            let r = CGFloat((int >> 16) & 0xFF) / 255.0
            let g = CGFloat((int >> 8) & 0xFF) / 255.0
            let b = CGFloat(int & 0xFF) / 255.0
            self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
        } else {
            self.init(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        }
    }
}
