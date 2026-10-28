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
        return downsample(cgImg: cgImg, maxDimension: 320)
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

// MARK: - Window Manager

@MainActor
public class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    @Published public var windows: [WindowItem] = []
    @Published public var selectedIndex: Int = 0
    @Published public var isVisible: Bool = false
    @Published public var hasScreenRecording: Bool = false
    @Published public var isAltTabEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAltTabEnabled, forKey: "alttab_enabled")
            gIsAltTabEnabled = isAltTabEnabled
        }
    }

    // Persistent MRU stack in memory to guarantee true back-and-forth AltTab behavior
    private var mruWindowIDs: [CGWindowID] = []

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

        if let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for item in cgList {
                let layer = item[kCGWindowLayer as String] as? Int ?? -1
                let wid = item[kCGWindowNumber as String] as? CGWindowID ?? 0
                let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let w = bounds["Width"] as? Double ?? 0
                let h = bounds["Height"] as? Double ?? 0
                let alpha = item[kCGWindowAlpha as String] as? Double ?? 1.0

                if layer == 0 && w >= 150 && h >= 100 && alpha > 0.1 && !seenWIDs.contains(wid) {
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

        // 3. Apply true MRU Sorting from mruWindowIDs stack
        if !mruWindowIDs.isEmpty {
            items.sort { a, b in
                guard let widA = a.windowID, let widB = b.windowID else { return false }
                let idxA = mruWindowIDs.firstIndex(of: widA)
                let idxB = mruWindowIDs.firstIndex(of: widB)
                if let iA = idxA, let iB = idxB {
                    return iA < iB
                }
                if idxA != nil { return true }
                if idxB != nil { return false }
                return false
            }
        }

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
            // Push active window to the top of the MRU stack!
            if let wid = target.windowID {
                mruWindowIDs.removeAll(where: { $0 == wid })
                mruWindowIDs.insert(wid, at: 0)
            }
            
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

        if let wid = item.windowID {
            mruWindowIDs.removeAll(where: { $0 == wid })
        }

        windows.remove(at: selectedIndex)
        if windows.isEmpty {
            hideOverlay()
        } else {
            selectedIndex = min(selectedIndex, windows.count - 1)
            previewSelectedWindow()
        }
    }

    public func quitSelectedApp() {
        guard isVisible, selectedIndex >= 0 && selectedIndex < windows.count else { return }
        let item = windows[selectedIndex]
        if let app = NSRunningApplication(processIdentifier: item.pid) {
            app.terminate()
        }

        let pidsToRemove = windows.filter { $0.pid == item.pid }.compactMap { $0.windowID }
        for w in pidsToRemove {
            mruWindowIDs.removeAll(where: { $0 == w })
        }

        windows.removeAll(where: { $0.pid == item.pid })
        if windows.isEmpty {
            hideOverlay()
        } else {
            selectedIndex = min(selectedIndex, windows.count - 1)
            previewSelectedWindow()
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

    // MARK: - Compact AltTab Overlay HUD Presentation

    private func showOverlay() {
        let cardWidth: CGFloat = 195
        let horizontalPadding: CGFloat = 36
        let calculatedWidth = CGFloat(windows.count) * cardWidth + horizontalPadding
        let panelHeight: CGFloat = 225

        if overlayPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: calculatedWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // ScreenSaver level ensures it floats above all regular and fullscreen windows!
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
        // Reuse the existing hosting controller: recreating it on every press
        // caused flicker, reset the scroll position and wasted RAM.

        guard let panel = overlayPanel else { return }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Center on screen where mouse currently resides
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.frame

        let totalWidth = min(calculatedWidth, screenRect.width - 60)
        let posX = screenRect.origin.x + (screenRect.width - totalWidth) / 2
        let posY = screenRect.origin.y + (screenRect.height - panelHeight) / 2

        panel.setFrame(NSRect(x: posX, y: posY, width: totalWidth, height: panelHeight), display: true)
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
