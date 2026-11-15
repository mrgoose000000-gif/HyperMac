import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import Combine

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
    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "screenshot_details_expanded")
        }
    }

    // Active Capture State
    @Published public var isActive: Bool = false
    @Published public var screenImage: CGImage? = nil {
        didSet {
            blurGeneration &+= 1
            blurredScreenImage = nil
            isPreparingBlur = false
            annotationError = nil
        }
    }
    @Published public private(set) var blurredScreenImage: CGImage?
    @Published public private(set) var isPreparingBlur = false
    @Published public private(set) var annotationError: String?
    private var blurGeneration = 0
    private let blurQueue = DispatchQueue(label: "com.opensource.hypermac.screenshot.blur", qos: .userInitiated)
    @Published public var screenNSImage: NSImage? = nil
    @Published public var screenFrame: NSRect = .zero
    @Published public var scaleFactor: CGFloat = 2.0

    // Selection Box (in screen-local coordinates 0...width, 0...height)
    @Published public var selectionRect: CGRect = .zero
    @Published public var hasSelection: Bool = false

    // Annotation Tools & Colors
    @Published public var currentTool: ScreenshotTool = .pen
    @Published public var selectedColorHex: String = "#FF3B30" // Default Red
    @Published public private(set) var strokes: [DrawnStroke] = []
    private var annotationUndoStack: [[DrawnStroke]] = []
    public var canUndoAnnotations: Bool {
        activeStroke != nil || isEditingText || !annotationUndoStack.isEmpty
    }
    @Published public var activeStroke: DrawnStroke? = nil
    @Published public var isColorPaletteExpanded: Bool = false

    // A native text editor owns keyboard input while a draft is open.
    @Published public var textDraft = ""
    @Published public var textFontSize: CGFloat = 22
    @Published public private(set) var textAnchor: CGPoint?
    private var editingTextID: UUID?
    public var isEditingText: Bool { textAnchor != nil }
    public var canCommitText: Bool { !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var canExport: Bool {
        !isPreparingBlur && (!strokes.contains { $0.tool == .blur } || blurredScreenImage != nil)
    }

    public var draftTextStroke: DrawnStroke? {
        guard let anchor = textAnchor, canCommitText else { return nil }
        return DrawnStroke(tool: .text,
                           points: [anchor, CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)],
                           colorHex: selectedColorHex, lineWidth: 0, text: textDraft, fontSize: textFontSize)
    }

    public var previewStrokes: [DrawnStroke] {
        let committed = strokes.filter { $0.id != editingTextID }
        return committed + (draftTextStroke.map { [$0] } ?? [])
    }

    // Drag Interaction Tracking
    @Published public var activeHandle: ResizeHandle? = nil
    @Published public var dragStartPoint: CGPoint = .zero
    @Published public var dragStartRect: CGRect = .zero
    @Published public var isDraggingSelection: Bool = false
    @Published public var isSpaceHeld: Bool = false

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
        self.isDetailsExpanded = UserDefaults.standard.bool(forKey: "screenshot_details_expanded")
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
        guard let targetScreen = (NSScreen.screens.first { $0.frame.contains(mouseLoc) }
            ?? NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first) else { return }

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
        cancelTextEditing()
        self.selectionRect = .zero
        self.hasSelection = false
        resetAnnotations()
        self.currentTool = .pen
        self.selectedColorHex = "#FF3B30"
        self.isColorPaletteExpanded = false
        self.toastMessage = nil
        self.isSpaceHeld = false

        // 3. Create or update overlay panel on the target screen
        createOrUpdateOverlayPanel(on: targetScreen)

        self.isActive = true
        gIsScreenshotActive = true
    }

    // MARK: - Capture Screen CGImage

    private func captureScreenImage(screen: NSScreen) -> CGImage? {
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryH = primary.frame.height
        let f = screen.frame
        let cgRect = CGRect(
            x: f.origin.x,
            y: primaryH - (f.origin.y + f.height),
            width: f.width,
            height: f.height
        )

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

    // MARK: - Switch Screen (Tab Shortcut for Multi-Display setups)

    public func switchScreen() {
        guard NSScreen.screens.count > 1 else { return }
        let screens = NSScreen.screens
        guard let currentIndex = screens.firstIndex(where: { $0.frame == self.screenFrame }) else { return }
        let nextIndex = (currentIndex + 1) % screens.count
        let nextScreen = screens[nextIndex]

        guard let capturedImage = captureScreenImage(screen: nextScreen) else { return }
        cancelTextEditing()
        self.screenFrame = nextScreen.frame
        self.screenImage = capturedImage
        self.scaleFactor = CGFloat(capturedImage.width) / nextScreen.frame.width
        self.screenNSImage = NSImage(cgImage: capturedImage, size: nextScreen.frame.size)

        self.selectionRect = .zero
        self.hasSelection = false
        resetAnnotations()

        createOrUpdateOverlayPanel(on: nextScreen)
        if currentTool == .blur { prepareBlur() }
    }

    // MARK: - Overlay Window Presentation

    private func createOrUpdateOverlayPanel(on screen: NSScreen) {
        if let existing = overlayPanel {
            existing.orderOut(nil)
            existing.contentView = nil
            overlayPanel = nil
        }

        let panel = ScreenshotOverlayPanel(contentRect: screen.frame)
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

        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Cancel Capture

    public func cancelCapture() {
        cancelTextEditing()
        if let panel = overlayPanel {
            panel.orderOut(nil)
            panel.contentView = nil
            overlayPanel = nil
        }
        self.isActive = false
        gIsScreenshotActive = false
        self.screenImage = nil
        self.screenNSImage = nil
        resetAnnotations()
        self.selectionRect = .zero
        self.hasSelection = false
        self.isSpaceHeld = false
    }

    // MARK: - Stroke Management

    public func undoLastStroke() {
        // The visible draft/gesture is newer than every committed annotation.
        // Cancel only that operation; never also remove the preceding stroke.
        if isEditingText { cancelTextEditing(); return }
        if activeStroke != nil { activeStroke = nil; return }
        guard let previous = annotationUndoStack.popLast() else { return }
        strokes = previous
    }

    public func resetAnnotations() {
        cancelTextEditing()
        annotationUndoStack.removeAll()
        activeStroke = nil
        strokes = []
    }

    public func clearAllStrokes() {
        cancelTextEditing()
        activeStroke = nil
        replaceAnnotations(with: [])
    }

    /// Record one completed user operation before publishing the new drawing.
    /// Avoid property-observer history and leave in-progress gestures out of the stack.
    private func replaceAnnotations(with next: [DrawnStroke]) {
        guard next != strokes else { return }
        annotationUndoStack.append(strokes)
        if annotationUndoStack.count > 100 { annotationUndoStack.removeFirst() }
        strokes = next
    }

    func appendStroke(_ stroke: DrawnStroke) {
        replaceAnnotations(with: strokes + [stroke])
    }

    func finishActiveStroke() {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        if stroke.tool == .blur {
            let bounds = ScreenshotAnnotationRenderer.rectangle(for: stroke)
            guard bounds.width >= 3, bounds.height >= 3 else { return }
        }
        appendStroke(stroke)
    }

    // MARK: - Text and Blur Tools

    public func selectTool(_ tool: ScreenshotTool) {
        commitTextEditing()
        activeStroke = nil
        annotationError = nil
        currentTool = tool
        if tool == .blur { prepareBlur() }
    }

    public func beginText(at point: CGPoint) {
        guard selectionRect.contains(point) else { return }
        commitTextEditing()
        if let existing = strokes.last(where: {
            $0.tool == .text && ScreenshotAnnotationRenderer.textBounds(for: $0).contains(point)
        }) {
            editingTextID = existing.id
            textAnchor = existing.points.first
            textDraft = existing.text
            textFontSize = existing.fontSize
            selectedColorHex = existing.colorHex
        } else {
            editingTextID = nil
            textAnchor = CGPoint(x: min(point.x, max(selectionRect.minX, selectionRect.maxX - 40)),
                                 y: min(point.y, max(selectionRect.minY, selectionRect.maxY - textFontSize * 1.5)))
            textDraft = ""
        }
        isSpaceHeld = false
        gIsSpacePressed = false
        gIsScreenshotEditingText = true
    }

    public func commitTextEditing() {
        guard isEditingText else { return }
        if let draft = draftTextStroke {
            if let id = editingTextID, let index = strokes.firstIndex(where: { $0.id == id }) {
                // Keep the original ID when editing an existing annotation.
                var updated = strokes
                updated[index] = DrawnStroke(id: id, tool: .text, points: draft.points,
                    colorHex: draft.colorHex, lineWidth: 0, text: draft.text, fontSize: draft.fontSize)
                replaceAnnotations(with: updated)
            } else {
                appendStroke(draft)
            }
        }
        cancelTextEditing()
    }

    public func cancelTextEditing() {
        textAnchor = nil
        editingTextID = nil
        textDraft = ""
        isSpaceHeld = false
        gIsSpacePressed = false
        gIsScreenshotEditingText = false
    }

    /// Filter the frozen image once per capture, off the main thread. Both preview and export use it.
    public func prepareBlur() {
        guard blurredScreenImage == nil, !isPreparingBlur, let image = screenImage else { return }
        annotationError = nil
        isPreparingBlur = true
        let generation = blurGeneration
        let scale = scaleFactor
        blurQueue.async { [weak self] in
            let result = ScreenshotAnnotationRenderer.pixelated(image, scale: scale)
            DispatchQueue.main.async {
                guard let self, self.blurGeneration == generation else { return }
                self.isPreparingBlur = false
                self.blurredScreenImage = result
                if result == nil {
                    self.annotationError = tr("Không tạo được vùng làm mờ. Chọn Làm mờ để thử lại.",
                                              "Could not prepare blur. Select Blur to retry.")
                }
            }
        }
    }

    // MARK: - High-Res Composite Render Engine (Maximum Retina Quality)

    public func renderCompositeImage() -> CGImage? {
        commitTextEditing()
        guard canExport else {
            annotationError = tr("Chưa thể xuất vùng làm mờ. Hãy thử lại công cụ Làm mờ.",
                                 "Blur is not ready. Please try the Blur tool again.")
            return nil
        }
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

        ctx.clip(to: selectionRect)

        // Render each stroke
        for stroke in strokes {
            ScreenshotAnnotationRenderer.draw(stroke, in: ctx, blurredImage: blurredScreenImage, scale: scale)
        }

        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - Copy Action (⌘C / LightShot Style)

    public func copyToClipboard() {
        guard let finalCG = renderCompositeImage() else { return }

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
        guard let finalCG = renderCompositeImage() else { return }

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

// Borderless NSPanel does not become key by default. The screenshot overlay must
// own keyboard focus for NSTextView/IME instead of leaving keys in the previous app.
final class ScreenshotOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
}
