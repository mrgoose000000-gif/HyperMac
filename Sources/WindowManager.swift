import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import SwiftUI
import Combine

// MARK: - Dynamic Symbol Loaders for Window IDs and Thumbnails

private typealias AXGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

private let axGetWindowSym: AXGetWindowFunc? = {
    if let sym = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") {
        return unsafeBitCast(sym, to: AXGetWindowFunc.self)
    }
    return nil
}()

private let cgCreateImgSym: CGWindowListCreateImageFunc? = {
    if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
       let sym = dlsym(handle, "CGWindowListCreateImage") {
        return unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
    }
    return nil
}()

/// Downsample a CGImage to a compact thumbnail (maxDimension ~320px) to conserve RAM.
/// Keeps memory usage at ~200KB per preview instead of ~33MB uncompressed raw Retina bitmap!
private func downsample(cgImg: CGImage, maxDimension: CGFloat = 320) -> NSImage? {
    let w = CGFloat(cgImg.width)
    let h = CGFloat(cgImg.height)
    guard w > 0 && h > 0 else { return nil }

    let scale = min(maxDimension / w, maxDimension / h)
    if scale >= 1.0 {
        return NSImage(cgImage: cgImg, size: NSSize(width: w / 2, height: h / 2))
    }

    let destWidth = max(1, Int(w * scale))
    let destHeight = max(1, Int(h * scale))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: destWidth,
        height: destHeight,
        bitsPerComponent: 8,
        bytesPerRow: destWidth * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return NSImage(cgImage: cgImg, size: NSSize(width: w / 2, height: h / 2))
    }

    context.interpolationQuality = .medium
    context.draw(cgImg, in: CGRect(x: 0, y: 0, width: destWidth, height: destHeight))

    guard let downsampledCG = context.makeImage() else {
        return NSImage(cgImage: cgImg, size: NSSize(width: w / 2, height: h / 2))
    }

    return NSImage(cgImage: downsampledCG, size: NSSize(width: CGFloat(destWidth) / 2, height: CGFloat(destHeight) / 2))
}

/// Capture thumbnail ONLY when Screen Recording permission is active.
/// We use option 8 (kCGWindowListOptionIncludingWindow) and CGRect.null to isolate ONLY that specific window!
private func captureThumbnail(wid: CGWindowID) -> NSImage? {
    guard CGPreflightScreenCaptureAccess(), let createFn = cgCreateImgSym, wid > 0 else {
        return nil
    }

    // Option 8 = optionIncludingWindow (isolates this exact window)
    // Option 1 = boundsIgnoreFraming (clean window without heavy dropshadow)
    // CGRect.null tells CoreGraphics to use the window's exact native frame!
    if let imgRef = createFn(CGRect.null, 8, wid, 1) {
        let cgImg = imgRef.takeRetainedValue()
        return downsample(cgImg: cgImg, maxDimension: 640)
    }
    return nil
}

// MARK: - Window Item Model

public struct WindowItem: Identifiable, Equatable {
    public let id: String
    public let pid: pid_t
    public let appName: String
    public let title: String
    public let icon: NSImage
    public let axElement: AXUIElement
    public var isMinimized: Bool
    public var windowID: CGWindowID?
    public var thumbnail: NSImage?

    public static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.isMinimized == rhs.isMinimized
    }
}

// MARK: - AltTab Adaptive Layout Model

public struct AltTabLayout: Equatable, Sendable {
    public var columns: Int
    public var totalRows: Int
    public var visibleRows: Int
    public var cardWidth: CGFloat
    public var cardHeight: CGFloat
    public var colSpacing: CGFloat
    public var rowSpacing: CGFloat
    public var panelWidth: CGFloat
    public var panelHeight: CGFloat
    public var isPortrait: Bool

    public static let standard = AltTabLayout(
        columns: 3,
        totalRows: 2,
        visibleRows: 2,
        cardWidth: 260,
        cardHeight: 188,
        colSpacing: 12,
        rowSpacing: 12,
        panelWidth: 840,
        panelHeight: 480,
        isPortrait: false
    )
}

// MARK: - Window Manager

@MainActor
public class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    @Published public var windows: [WindowItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var isVisible: Bool = false
    @Published public var currentLayout: AltTabLayout = .standard
    @Published public var hasScreenRecording: Bool = false
    @Published public var isAltTabEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAltTabEnabled, forKey: "alttab_enabled")
            gIsAltTabEnabled = isAltTabEnabled
        }
    }
    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "alttab_details_expanded")
        }
    }
    @Published public var showOnlyCurrentScreenWindows: Bool = false {
        didSet {
            UserDefaults.standard.set(showOnlyCurrentScreenWindows, forKey: "alttab_only_current_screen")
        }
    }

    public var isModifierHeld: Bool = false
    private var overlayPanel: NSPanel?
    private var isCommitInProgress: Bool = false
    private var thumbnailGeneration: Int = 0

    private init() {
        if UserDefaults.standard.object(forKey: "alttab_enabled") != nil {
            self.isAltTabEnabled = UserDefaults.standard.bool(forKey: "alttab_enabled")
        } else {
            self.isAltTabEnabled = true
        }
        gIsAltTabEnabled = self.isAltTabEnabled
        self.hasScreenRecording = CGPreflightScreenCaptureAccess()
        self.isDetailsExpanded = UserDefaults.standard.bool(forKey: "alttab_details_expanded")
        self.showOnlyCurrentScreenWindows = UserDefaults.standard.bool(forKey: "alttab_only_current_screen")
    }

    public func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - True MRU Window Enumeration (AltTab Genuine Z-Order Logic)

    public func refreshWindows() {
        self.hasScreenRecording = CGPreflightScreenCaptureAccess()
        let myPID = ProcessInfo.processInfo.processIdentifier

        // 1. Pre-fetch AXWindows and map them by their CGWindowID
        var axByWID: [CGWindowID: (app: String, title: String, icon: NSImage, elem: AXUIElement, pid: pid_t)] = [:]
        var minimizedItems: [WindowItem] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if pid == myPID { continue }
            let appName = app.localizedName ?? "App"
            let appIcon = app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!

            let appElement = AXUIElementCreateApplication(pid)
            _ = AXUIElementSetMessagingTimeout(appElement, 0.05)

            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWins = windowsRef as? [AXUIElement] {
                for win in axWins {
                    // Check subrole (exclude system dialogs, popups, sheets, unknown helpers)
                    var subroleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef)
                    let subrole = subroleRef as? String ?? ""
                    if subrole == "AXSystemDialog" || subrole == "AXUnknown" || subrole == "AXFloatingWindow" {
                        continue
                    }

                    // Check role (must be AXWindow)
                    var roleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleRef)
                    let role = roleRef as? String ?? ""
                    if role != "AXWindow" && !role.isEmpty {
                        continue
                    }

                    // Check size from AXUIElement (ignore 0x0 or auxiliary utility windows)
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
                    var size = CGSize.zero
                    if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

                    // Check minimized
                    var minRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
                    let isMin = (minRef as? Bool) ?? false

                    if !isMin && size.width > 0 && (size.width < 120 || size.height < 100) {
                        continue
                    }
                    if !isMin && size.width == 0 && size.height == 0 {
                        continue
                    }

                    // Check window title
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                    let rawTitle = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let cleanTitle = rawTitle.isEmpty ? appName : rawTitle

                    var wid: CGWindowID = 0
                    if let getWid = axGetWindowSym {
                        _ = getWid(win, &wid)
                    }

                    if isMin {
                        let id = "\(pid)_\(wid)_\(cleanTitle)"
                        minimizedItems.append(WindowItem(
                            id: id,
                            pid: pid,
                            appName: appName,
                            title: cleanTitle,
                            icon: appIcon,
                            axElement: win,
                            isMinimized: true,
                            windowID: wid > 0 ? wid : nil,
                            thumbnail: nil
                        ))
                    } else if wid > 0 {
                        axByWID[wid] = (appName, cleanTitle, appIcon, win, pid)
                    }
                }
            }
        }

        // 2. Iterate through CGWindowList in TRUE SCREEN Z-ORDER (frontmost to backmost)
        var items: [WindowItem] = []
        var seenWIDs = Set<CGWindowID>()

        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 956.0
        let activeAXFrame = CGRect(
            x: activeScreen.frame.origin.x,
            y: primaryHeight - (activeScreen.frame.origin.y + activeScreen.frame.height),
            width: activeScreen.frame.width,
            height: activeScreen.frame.height
        )

        if let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for item in cgList {
                let layer = item[kCGWindowLayer as String] as? Int ?? -1
                let wid = item[kCGWindowNumber as String] as? CGWindowID ?? 0
                let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let x = bounds["X"] as? Double ?? 0
                let y = bounds["Y"] as? Double ?? 0
                let w = bounds["Width"] as? Double ?? 0
                let h = bounds["Height"] as? Double ?? 0
                let alpha = item[kCGWindowAlpha as String] as? Double ?? 1.0

                if layer == 0 && w >= 150 && h >= 100 && alpha > 0.1 && !seenWIDs.contains(wid) {
                    // Screen isolation filter: only keep windows located on activeScreen
                    if showOnlyCurrentScreenWindows {
                        let winRect = CGRect(x: x, y: y, width: w, height: h)
                        let winCenter = CGPoint(x: winRect.midX, y: winRect.midY)
                        if !activeAXFrame.contains(winCenter) {
                            let intersection = activeAXFrame.intersection(winRect)
                            let overlap = (!intersection.isNull && !intersection.isEmpty) ? (intersection.width * intersection.height) : 0
                            if overlap < (winRect.width * winRect.height * 0.4) {
                                continue
                            }
                        }
                    }

                    if let info = axByWID[wid] {
                        seenWIDs.insert(wid)
                        // Thumbnails are captured asynchronously AFTER the HUD is
                        // already on screen, so opening AltTab stays instant.
                        let id = "\(info.pid)_\(wid)_\(info.title)"
                        items.append(WindowItem(
                            id: id,
                            pid: info.pid,
                            appName: info.app,
                            title: info.title,
                            icon: info.icon,
                            axElement: info.elem,
                            isMinimized: false,
                            windowID: wid,
                            thumbnail: nil
                        ))
                    }
                }
            }
        }

        // 3. True Screen Z-Order (Frontmost to Backmost)
        // CGWindowListCopyWindowInfo naturally maintains the exact real-time Z-order from WindowServer.
        // Append minimized windows at the end
        items.append(contentsOf: minimizedItems)

        self.windows = items
    }

    // MARK: - Shortcut Event Handling (Command + Tab or Option + Tab)

    public func handleShortcut(isShift: Bool) {
        guard isAltTabEnabled else { return }
        isModifierHeld = true

        if !isVisible {
            refreshWindows()
            guard !windows.isEmpty else {
                // Never leave the interceptor in a "HUD visible" state when
                // there is nothing to show, otherwise W/Q/arrow keys get eaten.
                isModifierHeld = false
                gIsAltTabVisible = false
                return
            }

            // Initial press selects index 1 (the immediately previous window in MRU!)
            if windows.count > 1 {
                selectedIndex = isShift ? (windows.count - 1) : 1
            } else {
                selectedIndex = 0
            }

            previewSelectedWindow()

            if isModifierHeld {
                // Show the HUD immediately; live previews stream in after.
                showOverlay()
                beginThumbnailCapture()
            } else {
                commitSelection()
            }
        } else {
            // Already visible: step forward or backward
            if isShift {
                selectPrevious()
            } else {
                selectNext()
            }
        }
    }

    public func handleOptionTab(isShift: Bool) {
        handleShortcut(isShift: isShift)
    }

    public func handleOptionReleased() {
        isModifierHeld = false
        if isVisible {
            commitSelection()
        }
    }

    /// Called by the event tap when the Command/Option modifier is released.
    /// Commits even if the overlay has not finished its first frame yet.
    public func handleModifierReleased() {
        isModifierHeld = false
        if isVisible || !windows.isEmpty {
            commitSelection()
        }
    }

    public func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        previewSelectedWindow()
    }

    public func selectPrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        previewSelectedWindow()
    }

    public func selectUp() {
        guard !windows.isEmpty else { return }
        let columns = max(1, currentLayout.columns)
        if selectedIndex - columns >= 0 {
            selectedIndex -= columns
        } else {
            // Wrap to bottom row in same column
            let target = selectedIndex + ((windows.count - 1 - selectedIndex) / columns) * columns
            selectedIndex = min(target, windows.count - 1)
        }
        previewSelectedWindow()
    }

    public func selectDown() {
        guard !windows.isEmpty else { return }
        let columns = max(1, currentLayout.columns)
        if selectedIndex + columns < windows.count {
            selectedIndex += columns
        } else {
            // Wrap to top row in same column
            selectedIndex = selectedIndex % columns
        }
        previewSelectedWindow()
    }

    public func previewSelectedWindow() {
        // Intentionally no-op:
        // We do NOT raise windows to the top while the user is simply cycling through the HUD.
        // This ensures the current window layout on screen remains completely undisturbed
        // until the user actually releases the shortcut to commit their selection.
    }

    // MARK: - Commit Selection (Update MRU stack & Activate Target Window)

    public func commitSelection() {
        guard !isCommitInProgress else { return }
        isCommitInProgress = true
        isModifierHeld = false

        let targetIndex = selectedIndex
        let targetItem = (targetIndex >= 0 && targetIndex < windows.count) ? windows[targetIndex] : nil

        hideOverlay()

        if let target = targetItem {
            activateWindow(target)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isCommitInProgress = false
        }
    }

    public func cancel() {
        isModifierHeld = false
        hideOverlay()
    }

    public func activateWindow(_ item: WindowItem) {
        // 1. Unminimize if minimized
        if item.isMinimized {
            AXUIElementSetAttributeValue(item.axElement, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }

        // 2. Unhide app if hidden (Cmd+H)
        if let app = NSRunningApplication(processIdentifier: item.pid) {
            if app.isHidden {
                app.unhide()
            }
        }

        // 3. Raise window via Accessibility
        AXUIElementPerformAction(item.axElement, kAXRaiseAction as CFString)

        // 4. Activate owning application WITHOUT activateAllWindows (preserves exact z-order)
        if let app = NSRunningApplication(processIdentifier: item.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
            if #available(macOS 14.0, *) {
                app.activate()
            }
        }
    }

    public func closeSelectedWindow() {
        guard isVisible, selectedIndex >= 0 && selectedIndex < windows.count else { return }
        let item = windows[selectedIndex]

        var closeBtnRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(item.axElement, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
           let closeBtn = closeBtnRef {
            AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
        }

        windows.remove(at: selectedIndex)
        if windows.isEmpty {
            hideOverlay()
        } else {
            selectedIndex = min(selectedIndex, windows.count - 1)
            previewSelectedWindow()
            showOverlay()
        }
    }

    public func quitSelectedApp() {
        guard isVisible, selectedIndex >= 0 && selectedIndex < windows.count else { return }
        let item = windows[selectedIndex]
        if let app = NSRunningApplication(processIdentifier: item.pid) {
            app.terminate()
        }

        windows.removeAll(where: { $0.pid == item.pid })
        if windows.isEmpty {
            hideOverlay()
        } else {
            selectedIndex = min(selectedIndex, windows.count - 1)
            previewSelectedWindow()
            showOverlay()
        }
    }

    // MARK: - Async Thumbnail Capture (keeps AltTab instant)

    /// Captures live previews on a background queue after the HUD is visible.
    /// Opening the switcher stays instant because AX enumeration no longer
    /// waits for Retina window snapshots to render.
    private func beginThumbnailCapture() {
        thumbnailGeneration &+= 1
        let generation = thumbnailGeneration

        let targets: [(id: String, wid: CGWindowID)] = windows.compactMap { item in
            guard let wid = item.windowID, wid > 0 else { return nil }
            return (item.id, wid)
        }
        guard !targets.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            for target in targets {
                guard let image = captureThumbnail(wid: target.wid) else { continue }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.thumbnailGeneration == generation,
                          self.isVisible else { return }
                    if let index = self.windows.firstIndex(where: { $0.id == target.id }) {
                        self.windows[index].thumbnail = image
                    }
                }
            }
        }
    }

    // MARK: - Multi-row Grid Geometry Calculation

    public static func computeGrid(windowCount: Int) -> (columns: Int, rows: Int) {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = computeLayout(windowCount: windowCount, screenRect: frame)
        return (layout.columns, layout.totalRows)
    }

    public static func computeLayout(windowCount: Int, screenRect: NSRect) -> AltTabLayout {
        let count = max(1, windowCount)
        let safeW = screenRect.width > 0 ? screenRect.width : 1440
        let safeH = screenRect.height > 0 ? screenRect.height : 900
        let isPortrait = safeW < safeH

        let hPadding: CGFloat = 36 // 18pt each side
        let vPadding: CGFloat = 92 // Header ~44 + Footer ~36 + Vertical padding ~12
        let colSpacing: CGFloat = 12
        let rowSpacing: CGFloat = 12
        let cardRatio: CGFloat = 260.0 / 188.0 // 1.383

        // Usable bounding box with safe margins to never touch/overflow screen edges
        let maxUsableWidth = max(280, safeW - (isPortrait ? 32 : 48))
        let maxUsableHeight = max(320, safeH - (isPortrait ? 48 : 64))

        // 1. Determine optimal columns & total rows
        var cols: Int
        if isPortrait {
            // PORTRAIT ORIENTATION (Vertical Monitor)
            // Stacks vertically to take full advantage of height without horizontal squeezing
            if count <= 1 {
                cols = 1
            } else if count <= 2 {
                cols = maxUsableWidth >= 560 ? 2 : 1
            } else if count <= 8 {
                cols = 2
            } else if count <= 15 {
                cols = maxUsableWidth >= 800 ? 3 : 2
            } else {
                cols = maxUsableWidth >= 850 ? 3 : 2
            }
        } else {
            // LANDSCAPE ORIENTATION (Horizontal Monitor / Standard Laptop)
            if count <= 4 {
                cols = count
            } else if count <= 6 {
                cols = 3
            } else if count <= 8 {
                cols = 4
            } else if count <= 12 {
                cols = 4
            } else if count <= 15 {
                cols = 5
            } else {
                cols = 5
            }
        }

        let totalRows = max(1, Int(ceil(Double(count) / Double(cols))))

        // 2. Determine max visible rows before scrolling starts
        let maxCardW: CGFloat = 260.0
        let maxCardH: CGFloat = 188.0
        let minCardW: CGFloat = 150.0

        let maxAllowedVisibleRows: Int
        if isPortrait {
            // In portrait, we have plenty of vertical room (can show up to 4 or 5 rows)
            let possibleRows = Int((maxUsableHeight - vPadding) / (maxCardH + rowSpacing))
            maxAllowedVisibleRows = max(2, min(5, possibleRows))
        } else {
            // In landscape, height is tighter (show at most 3 rows without scrolling)
            let possibleRows = Int((maxUsableHeight - vPadding) / (maxCardH + rowSpacing))
            maxAllowedVisibleRows = max(1, min(3, possibleRows))
        }
        let visibleRows = min(totalRows, max(1, maxAllowedVisibleRows))

        // 3. Dynamic card scaling: compute max cardWidth that satisfies both width & height constraints
        let availableGridW = maxUsableWidth - hPadding - CGFloat(max(0, cols - 1)) * colSpacing
        let maxCardWByScreenW = availableGridW / CGFloat(cols)

        let availableGridH = maxUsableHeight - vPadding - CGFloat(max(0, visibleRows - 1)) * rowSpacing
        let maxCardHByScreenH = availableGridH / CGFloat(visibleRows)
        let maxCardWByScreenH = maxCardHByScreenH * cardRatio

        var cardWidth = min(maxCardW, min(maxCardWByScreenW, maxCardWByScreenH))
        cardWidth = max(minCardW, cardWidth)
        let cardHeight = round(cardWidth / cardRatio)

        // 4. Panel dimensions (with comfortable minimum width so footer shortcuts and title never squish)
        let minPanelW: CGFloat = isPortrait ? 420.0 : 440.0
        let gridWidth = CGFloat(cols) * cardWidth + CGFloat(max(0, cols - 1)) * colSpacing
        let panelWidth = min(safeW - 20, max(minPanelW, gridWidth + hPadding))

        let gridHeight = CGFloat(visibleRows) * cardHeight + CGFloat(max(0, visibleRows - 1)) * rowSpacing
        let panelHeight = min(safeH - 24, gridHeight + vPadding)

        return AltTabLayout(
            columns: cols,
            totalRows: totalRows,
            visibleRows: visibleRows,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            colSpacing: colSpacing,
            rowSpacing: rowSpacing,
            panelWidth: panelWidth,
            panelHeight: panelHeight,
            isPortrait: isPortrait
        )
    }

    // MARK: - Multi-row AltTab Overlay HUD Presentation

    private func showOverlay() {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenVisibleFrame = screen.visibleFrame

        let layout = Self.computeLayout(windowCount: windows.count, screenRect: screenVisibleFrame)
        self.currentLayout = layout

        let totalWidth = layout.panelWidth
        let totalHeight = layout.panelHeight

        if overlayPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.contentViewController = NSHostingController(
                rootView: AltTabOverlayView(windowManager: self)
            )
            self.overlayPanel = panel
        }

        guard let panel = overlayPanel else { return }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Center on the visible frame of the active screen
        let posX = screenVisibleFrame.origin.x + (screenVisibleFrame.width - totalWidth) / 2
        let posY = screenVisibleFrame.origin.y + (screenVisibleFrame.height - totalHeight) / 2

        panel.setFrame(NSRect(x: posX, y: posY, width: totalWidth, height: totalHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        self.isVisible = true
        gIsAltTabVisible = true
    }

    private func hideOverlay() {
        // Invalidate any in-flight thumbnail captures.
        thumbnailGeneration &+= 1
        overlayPanel?.orderOut(nil)
        self.isVisible = false
        gIsAltTabVisible = false

        // Purge cached window thumbnails and items immediately to release RAM!
        for i in 0..<windows.count {
            windows[i].thumbnail = nil
        }
        self.windows.removeAll(keepingCapacity: false)
    }
}
