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
        }
    }
    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "window_snap_details_expanded")
        }
    }

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

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
        _ = AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        return (win, pos, size)
    }

    // MARK: - Apply Frame to Window (Robust Display Transfer)

    private func applyFrame(to window: AXUIElement, rect: CGRect) {
        var newPos = rect.origin
        var newSize = rect.size

        guard let posVal = AXValueCreate(.cgPoint, &newPos),
              let sizeVal = AXValueCreate(.cgSize, &newSize) else { return }

        // Phase 1: Move window to target display coordinate space
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)

        // Phase 2: After 30ms settlement, re-apply size and position.
        // macOS WindowServer requires a brief window of time to re-bind the window backing
        // store to the new display context before accepting sizes that exceed the previous display limits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.030) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }

        // Phase 3: Secondary check at 75ms for complex apps (VS Code, Electron, Chrome)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) {
            var currSize = CGSize.zero
            var sRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sRef) == .success,
               let s = sRef {
                AXValueGetValue(s as! AXValue, .cgSize, &currSize)
                if abs(currSize.width - newSize.width) > 2.0 || abs(currSize.height - newSize.height) > 2.0 {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
                }
            }
        }
    }

    // MARK: - Snap Action Calculation

    public func calculateSnapRect(action: SnapAction, visible: CGRect) -> CGRect {
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

        case .center:
            let w = min(floor(visible.width * 0.78), 1200)
            let h = min(floor(visible.height * 0.82), 850)
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
        let screen = screenContaining(windowRect: windowRect, in: screens)
        let visible = Self.axVisibleFrame(for: screen)

        let newFrame = calculateSnapRect(action: action, visible: visible)
        applyFrame(to: target.element, rect: newFrame)
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
            destination: targetVisible
        )

        appLog("🖥 Transfer: from [\(currentScreen.localizedName)] to [\(targetScreen.localizedName)]")
        appLog("   window: \(windowRect) -> transferred: \(transferredRect)")

        applyFrame(to: target.element, rect: transferredRect)
    }

    // MARK: - Rectangle Proportional Cross-Display Calculation

    /// Calculates destination window frame preserving exact screen proportions, snap states, and margins
    public static func calculateCrossDisplayRect(window: CGRect, source: CGRect, destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else {
            return window
        }

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

        // 3. Rectangle Proportional Mapping (relativePositionedRect)
        // Retains exact proportion of screen coverage so floating windows feel natural across differing DPIs/resolutions
        var newW = round(widthFrac * destination.width)
        var newH = round(heightFrac * destination.height)
        newW = max(350, min(newW, destination.width))
        newH = max(250, min(newH, destination.height))

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
