import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Window Snap Actions

public enum SnapAction {
    case leftHalf
    case rightHalf
    case maximize
    case center
    case restore
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

// MARK: - Window Snap Manager (Rectangle Architecture)

@MainActor
public class WindowSnapManager: ObservableObject {
    public static let shared = WindowSnapManager()

    @Published public var isSnapEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSnapEnabled, forKey: "window_snap_enabled")
            gIsWindowSnapEnabled = isSnapEnabled
        }
    }
    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "window_snap_details_expanded")
        }
    }

    private struct WindowKey: Hashable {
        let element: AXUIElement
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }
    private var frameHistory = WindowFrameHistory<WindowKey>()

    private init() {
        if UserDefaults.standard.object(forKey: "window_snap_enabled") != nil {
            self.isSnapEnabled = UserDefaults.standard.bool(forKey: "window_snap_enabled")
        } else {
            self.isSnapEnabled = true
        }
        self.isDetailsExpanded = UserDefaults.standard.bool(forKey: "window_snap_details_expanded")
    }

    // MARK: - Coordinate Conversion (Cocoa Bottom-Left to Accessibility Top-Left)

    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 956.0
    }

    /// Physical screen frame in AX coordinates (origin at top-left of primary screen)
    public static func axFrame(for screen: NSScreen) -> CGRect {
        let f = screen.frame
        let axY = primaryScreenHeight - (f.origin.y + f.height)
        return CGRect(x: f.origin.x, y: axY, width: f.width, height: f.height)
    }

    /// Usable screen area in AX coordinates, accounting for menu bar, notch, and dock
    public static func axVisibleFrame(for screen: NSScreen) -> CGRect {
        let f = screen.frame
        let vf = screen.visibleFrame
        let axY = primaryScreenHeight - (f.origin.y + f.height)

        // Top menu bar / status bar margin
        var topMargin = screen.safeAreaInsets.top
        if topMargin <= 0 {
            topMargin = (screen == NSScreen.screens.first) ? 33.0 : 30.0
        }

        // Bottom dock margin (if dock is visible and not auto-hidden)
        var bottomMargin: CGFloat = 0.0
        if vf.origin.y > f.origin.y {
            bottomMargin = vf.origin.y - f.origin.y
        }

        // Left / Right dock margin
        var leftMargin: CGFloat = 0.0
        if vf.origin.x > f.origin.x {
            leftMargin = vf.origin.x - f.origin.x
        }
        var rightMargin: CGFloat = 0.0
        if f.maxX > vf.maxX {
            rightMargin = f.maxX - vf.maxX
        }

        let width = f.width - leftMargin - rightMargin
        let height = f.height - topMargin - bottomMargin
        return CGRect(x: f.origin.x + leftMargin, y: axY + topMargin, width: width, height: height)
    }

    // MARK: - Screen Detection & Ordering (Rectangle ScreenDetection)

    /// Sort screens geometrically from left to right (and top to bottom for ties)
    public func orderedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens }
        return screens.sorted {
            if $0.frame.minX != $1.frame.minX {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY > $1.frame.minY
        }
    }

    /// Detect screen containing window by calculating maximum overlap area
    private func screenContaining(windowRect: CGRect, in screens: [NSScreen]) -> NSScreen {
        var bestScreen: NSScreen = screens.first ?? (NSScreen.main ?? NSScreen.screens[0])
        var largestPercentage: CGFloat = 0.0

        for screen in screens {
            let sAX = Self.axFrame(for: screen)
            if sAX.contains(windowRect) {
                return screen
            }
            let intersection = sAX.intersection(windowRect)
            if !intersection.isNull && !intersection.isEmpty {
                let area = intersection.width * intersection.height
                let windowArea = max(1.0, windowRect.width * windowRect.height)
                let pct = area / windowArea
                if pct > largestPercentage {
                    largestPercentage = pct
                    bestScreen = screen
                }
            }
        }

        // Fallback: screen whose center is closest to window center
        if largestPercentage <= 0.001 {
            let winCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
            var minDist: CGFloat = .greatestFiniteMagnitude
            for screen in screens {
                let sAX = Self.axFrame(for: screen)
                let dist = hypot(winCenter.x - sAX.midX, winCenter.y - sAX.midY)
                if dist < minDist {
                    minDist = dist
                    bestScreen = screen
                }
            }
        }

        return bestScreen
    }

    // MARK: - Get Active Focused Window

    private func getFocusedWindow() -> (element: AXUIElement, currentPos: CGPoint, currentSize: CGSize)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElem = AXUIElementCreateApplication(frontApp.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(appElem, 0.1)

        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedRef) != .success {
            var winsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winsRef) == .success,
               let wins = winsRef as? [AXUIElement], let first = wins.first {
                focusedRef = first
            }
        }

        guard let win = focusedRef as! AXUIElement? else { return nil }

        guard let frame = readFrame(of: win) else { return nil }
        return (win, frame.origin, frame.size)
    }

    private func readFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, let s = sizeRef,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &position),
              AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0,
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Apply Frame to Window (Robust Display Transfer)

    private func applyFrame(to window: AXUIElement, rect: CGRect, current: CGRect, restoring: Bool = false) {
        var newPos = rect.origin
        var newSize = rect.size
        guard let posVal = AXValueCreate(.cgPoint, &newPos),
              let sizeVal = AXValueCreate(.cgSize, &newSize) else { return }
        let key = WindowKey(element: window)
        let token = frameHistory.begin(key, current: current, target: rect, restoring: restoring)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)

        // Retry only while this operation is still current for this particular window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.030) { [weak self] in
            guard let self, self.frameHistory.isCurrent(key, token: token) else { return }
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { [weak self] in
            guard let self, self.frameHistory.isCurrent(key, token: token), let actual = self.readFrame(of: window) else { return }
            if abs(actual.width - rect.width) > 2 || abs(actual.height - rect.height) > 2 {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
            }
            if let settled = self.readFrame(of: window) { self.frameHistory.settle(key, token: token, actual: settled) }
        }
    }

    // MARK: - Snap Action Calculation

    public func calculateSnapRect(action: SnapAction, visible: CGRect, currentWindowRect: CGRect? = nil) -> CGRect {
        switch action {
        case .leftHalf:
            let halfW = floor(visible.width / 2.0)
            return CGRect(
                x: visible.origin.x,
                y: visible.origin.y,
                width: halfW,
                height: visible.height
            )

        case .rightHalf:
            let halfW = floor(visible.width / 2.0)
            return CGRect(
                x: visible.origin.x + (visible.width - halfW),
                y: visible.origin.y,
                width: halfW,
                height: visible.height
            )

        case .maximize:
            return visible

        case .restore:
            // Restoring needs per-window history and is handled in snapActiveWindow.
            return currentWindowRect ?? visible

        case .center:
            // Rectangle standard: Preserve window size, center on target display
            var w: CGFloat
            var h: CGFloat
            if let cur = currentWindowRect, cur.width > 50, cur.height > 50 {
                w = min(cur.width, visible.width)
                h = min(cur.height, visible.height)
            } else {
                w = min(floor(visible.width * 0.78), 1200)
                h = min(floor(visible.height * 0.82), 850)
            }
            return CGRect(
                x: visible.origin.x + (visible.width - w) / 2.0,
                y: visible.origin.y + (visible.height - h) / 2.0,
                width: w,
                height: h
            )

        case .topHalf:
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x,
                y: visible.origin.y,
                width: visible.width,
                height: halfH
            )

        case .bottomHalf:
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x,
                y: visible.origin.y + (visible.height - halfH),
                width: visible.width,
                height: halfH
            )

        case .topLeft:
            let halfW = floor(visible.width / 2.0)
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x,
                y: visible.origin.y,
                width: halfW,
                height: halfH
            )

        case .topRight:
            let halfW = floor(visible.width / 2.0)
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x + (visible.width - halfW),
                y: visible.origin.y,
                width: halfW,
                height: halfH
            )

        case .bottomLeft:
            let halfW = floor(visible.width / 2.0)
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x,
                y: visible.origin.y + (visible.height - halfH),
                width: halfW,
                height: halfH
            )

        case .bottomRight:
            let halfW = floor(visible.width / 2.0)
            let halfH = floor(visible.height / 2.0)
            return CGRect(
                x: visible.origin.x + (visible.width - halfW),
                y: visible.origin.y + (visible.height - halfH),
                width: halfW,
                height: halfH
            )
        }
    }

    // MARK: - Snap Active Window (Option + Control + Arrow keys)

    public func snapActiveWindow(_ action: SnapAction) {
        guard isSnapEnabled else { return }
        guard let target = getFocusedWindow() else { return }

        let windowRect = CGRect(origin: target.currentPos, size: target.currentSize)
        let screens = orderedScreens()
        guard !screens.isEmpty else { return }
        let screen = screenContaining(windowRect: windowRect, in: screens)
        let visible = Self.axVisibleFrame(for: screen)

        if action == .restore {
            guard let original = frameHistory.original(for: WindowKey(element: target.element)) else { return }
            let restored = WindowFrameHistory<WindowKey>.visibleRestoreFrame(original,
                screens: screens.map(Self.axVisibleFrame), fallback: visible)
            applyFrame(to: target.element, rect: restored, current: windowRect, restoring: true)
            return
        }
        let newFrame = calculateSnapRect(action: action, visible: visible, currentWindowRect: windowRect)
        applyFrame(to: target.element, rect: newFrame, current: windowRect)
    }

    // MARK: - Cross-Display Window Transfer (Option + Command + Arrow keys)

    public func moveActiveWindowToDisplay(isNext: Bool) {
        guard isSnapEnabled else {
            appLog("⚠️ SnapManager: isSnapEnabled is false")
            return
        }
        guard let target = getFocusedWindow() else {
            appLog("⚠️ SnapManager: No focused window found")
            return
        }

        let screens = orderedScreens()
        guard screens.count > 1 else {
            appLog("⚠️ SnapManager: Only 1 screen available, cannot move across displays")
            return
        }

        let windowRect = CGRect(origin: target.currentPos, size: target.currentSize)
        let currentScreen = screenContaining(windowRect: windowRect, in: screens)

        guard let curIndex = screens.firstIndex(of: currentScreen) else { return }
        let targetIndex = isNext
            ? (curIndex + 1) % screens.count
            : (curIndex - 1 + screens.count) % screens.count

        let targetScreen = screens[targetIndex]
        let curVisible = Self.axVisibleFrame(for: currentScreen)
        let targetVisible = Self.axVisibleFrame(for: targetScreen)

        let transferredRect = Self.calculateCrossDisplayRect(
            window: windowRect,
            source: curVisible,
            destination: targetVisible,
            mode: WindowDisplayTransferSettings.shared.mode
        )

        appLog("🖥 Transfer: from [\(currentScreen.localizedName)] to [\(targetScreen.localizedName)]")
        appLog("   window: \(windowRect) -> transferred: \(transferredRect)")

        applyFrame(to: target.element, rect: transferredRect, current: windowRect)
    }

    // MARK: - Cross-Display Sizing Modes

    public static func calculateCrossDisplayRect(window: CGRect, source: CGRect, destination: CGRect,
                                                 mode: WindowDisplayTransferMode = .keepSize) -> CGRect {
        guard WindowDisplayTransfer.isValid(window), WindowDisplayTransfer.isValid(source),
              WindowDisplayTransfer.isValid(destination) else { return window }
        switch mode {
        case .keepSize:
            return WindowDisplayTransfer.keepingSize(window: window, source: source, destination: destination)
        case .proportional:
            return calculateProportionalCrossDisplayRect(window: window, source: source, destination: destination)
        }
    }

    /// Original HyperMac behavior: preserve screen coverage and recognized half/corner layouts.
    private static func calculateProportionalCrossDisplayRect(window: CGRect, source: CGRect, destination: CGRect) -> CGRect {

        let originXFrac = (window.minX - source.minX) / source.width
        let originYFrac = (window.minY - source.minY) / source.height
        let widthFrac = window.width / source.width
        let heightFrac = window.height / source.height

        // 1. Full Screen / Maximized Window Detection
        // If window covers ~94%+ width and ~92%+ height (or within 35px tolerance), maximize on destination
        let isNearlyFullWidth = widthFrac >= 0.94 || abs(window.width - source.width) <= 35.0
        let isNearlyFullHeight = heightFrac >= 0.92 || abs(window.height - source.height) <= 35.0

        if isNearlyFullWidth && isNearlyFullHeight {
            return destination
        }

        // 2. Snap Detection (Left Half / Right Half / Top Half / Bottom Half / Corners)
        let touchesLeft = abs(window.minX - source.minX) <= 32.0
        let touchesRight = abs(window.maxX - source.maxX) <= 32.0
        let touchesTop = abs(window.minY - source.minY) <= 32.0
        let touchesBottom = abs(window.maxY - source.maxY) <= 32.0
        let isHalfWidth = abs(widthFrac - 0.5) <= 0.08
        let isHalfHeight = abs(heightFrac - 0.5) <= 0.08

        // Quarter Screen (4 Corners)
        if isHalfWidth && isHalfHeight {
            let halfW = floor(destination.width / 2.0)
            let halfH = floor(destination.height / 2.0)
            if touchesLeft && touchesTop {
                return CGRect(x: destination.minX, y: destination.minY, width: halfW, height: halfH)
            }
            if touchesRight && touchesTop {
                return CGRect(x: destination.minX + (destination.width - halfW), y: destination.minY, width: halfW, height: halfH)
            }
            if touchesLeft && touchesBottom {
                return CGRect(x: destination.minX, y: destination.minY + (destination.height - halfH), width: halfW, height: halfH)
            }
            if touchesRight && touchesBottom {
                return CGRect(x: destination.minX + (destination.width - halfW), y: destination.minY + (destination.height - halfH), width: halfW, height: halfH)
            }
        }

        // Left Half
        if touchesLeft && isNearlyFullHeight && isHalfWidth {
            let halfW = floor(destination.width / 2.0)
            return CGRect(x: destination.minX, y: destination.minY, width: halfW, height: destination.height)
        }

        // Right Half
        if touchesRight && isNearlyFullHeight && isHalfWidth {
            let halfW = floor(destination.width / 2.0)
            return CGRect(x: destination.minX + (destination.width - halfW), y: destination.minY, width: halfW, height: destination.height)
        }

        // Top Half
        if touchesTop && isNearlyFullWidth && isHalfHeight {
            let halfH = floor(destination.height / 2.0)
            return CGRect(x: destination.minX, y: destination.minY, width: destination.width, height: halfH)
        }

        // Bottom Half
        if touchesBottom && isNearlyFullWidth && isHalfHeight {
            let halfH = floor(destination.height / 2.0)
            return CGRect(x: destination.minX, y: destination.minY + (destination.height - halfH), width: destination.width, height: halfH)
        }

        // 3. Proportional mapping for ordinary windows
        // Retains exact proportion of screen coverage so floating windows feel natural across differing DPIs/resolutions
        var newW = round(widthFrac * destination.width)
        var newH = round(heightFrac * destination.height)
        newW = min(destination.width, max(350, newW))
        newH = min(destination.height, max(250, newH))

        var newX = destination.minX + (originXFrac * destination.width)
        var newY = destination.minY + (originYFrac * destination.height)

        // Keep edge-alignment flush if window was hugging source edge
        if touchesLeft { newX = destination.minX }
        if touchesRight { newX = destination.maxX - newW }
        if touchesTop { newY = destination.minY }
        if touchesBottom { newY = destination.maxY - newH }

        // Final bounds constraint
        newX = max(destination.minX, min(newX, destination.maxX - newW))
        newY = max(destination.minY, min(newY, destination.maxY - newH))

        return CGRect(x: newX, y: newY, width: newW, height: newH)
    }
}
