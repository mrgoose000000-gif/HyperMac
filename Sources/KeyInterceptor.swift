import Foundation
import CoreGraphics
import AppKit

// Apple standard definitions from ev_keymap.h:
private let NX_SYSDEFINED: UInt32 = 14
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3

// MARK: - Mouse Chord State Tracking (Session-safe)
private var isLeftMouseDown = false
private var isRightMouseDown = false
private var chordTriggered = false
private var leftDownTime: TimeInterval = 0
private var rightDownTime: TimeInterval = 0
private var leftDownLocation: CGPoint = .zero
private var rightDownLocation: CGPoint = .zero
private var chordTriggerTime: TimeInterval = 0

/// Posts a synthetic mouseUp event for the button whose mouseDown already leaked to the active app
/// milliseconds before the second button completed the chord. This prevents the active app/window
/// from remaining stuck in a dragging/selecting state after Mission Control opens.
private func postSyntheticMouseUp(button: CGMouseButton, location: CGPoint) {
    let mouseType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
    let src = CGEventSource(stateID: .combinedSessionState)
    guard let upEvent = CGEvent(mouseEventSource: src, mouseType: mouseType, mouseCursorPosition: location, mouseButton: button) else {
        return
    }
    gIsSynthesizingEvent = true
    upEvent.post(tap: .cgSessionEventTap)
    gIsSynthesizingEvent = false
}

// Fast lock-free flags for eventTapCallback
public var gIsMouseChordEnabled: Bool = true
public var gIsAltTabEnabled: Bool = true
public var gIsAltTabVisible: Bool = false
public var gIsClipboardEnabled: Bool = true
public var gIsClipboardHUDVisible: Bool = false
public var gIsClipboardSearchEmpty: Bool = true
public var gClipboardShortcutKeycode: Int64 = 8
public var gIsCursorBasedBrightnessEnabled: Bool = true
public var gIsScreenshotEnabled: Bool = true
public var gIsScreenshotActive: Bool = false
public var gIsSpacePressed: Bool = false
private var gActiveModifierMask: CGEventFlags? = nil
private var gCurrentTap: CFMachPort? = nil
private var gLastSnapArrowKey: Int64 = 0
private var gLastSnapArrowTime: TimeInterval = 0

/// Maps macOS virtual keycodes for 1...9 to their 0-based clipboard row index.
private func clipboardQuickPasteIndex(for keyCode: Int64) -> Int? {
    switch keyCode {
    case 18: return 0 // 1
    case 19: return 1 // 2
    case 20: return 2 // 3
    case 21: return 3 // 4
    case 23: return 4 // 5
    case 22: return 5 // 6
    case 26: return 6 // 7
    case 28: return 7 // 8
    case 25: return 8 // 9
    default: return nil
    }
}

private func triggerMissionControl() {
    DispatchQueue.main.async {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if error != nil {
                // Fallback: Post Control + Up Arrow via session tap
                let src = CGEventSource(stateID: .combinedSessionState)
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 126, keyDown: true) {
                    down.flags = .maskControl
                    down.post(tap: .cgSessionEventTap)
                }
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 126, keyDown: false) {
                    up.flags = .maskControl
                    up.post(tap: .cgSessionEventTap)
                }
            }
        }
    }
}

// MARK: - Event Tap Callback (Session level, zero main-sync)
//
// The tap only borrows `event` from WindowServer — always hand it back with
// passUnretained. passRetained adds an extra retain that is never balanced, so
// every key/mouse event (plus its HIDEvent) leaks and memory grows forever.

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // 0. Synthetic event bypass: allow HyperMac-synthesized events (e.g. Cmd+C, Opt+Cmd+V) to pass through without interception
    if gIsSynthesizingEvent {
        return Unmanaged.passUnretained(event)
    }

    // 1. Safety handler for system tap disable
    if type == .tapDisabledByUserInput {
        // User revoked permission in System Settings -> STOP cleanly! Do NOT fight WindowServer!
        appLog("⚠️ EventTap was disabled by user/system in Accessibility settings. Stopping.")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                KeyInterceptor.shared.stop()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .tapDisabledByTimeout {
        // Timeout from macOS -> Re-enable safely
        if let tap = gCurrentTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged {
        let flags = event.flags
        if !flags.contains(.maskControl) || !flags.contains(.maskAlternate) {
            gLastSnapArrowKey = 0
            gLastSnapArrowTime = 0
        }
    }

    // 2. Mouse Chording: Simultaneous Left + Right Click -> F3 (Mission Control)
    if gIsMouseChordEnabled {
        let now = Date().timeIntervalSince1970
        let chordWindow: TimeInterval = 0.20 // 200ms window for simultaneous press (prevents false-triggers during normal drag)
        let maxChordDrift: CGFloat = 24.0    // Max cursor movement between first and second button press

        switch type {
        case .leftMouseDown:
            let loc = event.location
            let rightPhysicallyDown = isRightMouseDown &&
                                      (now - rightDownTime <= chordWindow) &&
                                      CGEventSource.buttonState(.combinedSessionState, button: .right) &&
                                      (hypot(loc.x - rightDownLocation.x, loc.y - rightDownLocation.y) <= maxChordDrift)
            isLeftMouseDown = true
            leftDownTime = now
            leftDownLocation = loc

            if rightPhysicallyDown {
                chordTriggered = true
                chordTriggerTime = now
                // Right mouseDown already leaked to the active app milliseconds ago -> immediately send synthetic rightMouseUp
                // so the app releases its right-button state before Mission Control activates!
                postSyntheticMouseUp(button: .right, location: rightDownLocation)
                triggerMissionControl()
                return nil // Swallow leftMouseDown
            } else {
                // Fresh single left click: ensure any stale chord state is cleared so its leftMouseUp is never swallowed
                chordTriggered = false
                isRightMouseDown = false
            }

        case .rightMouseDown:
            let loc = event.location
            let leftPhysicallyDown = isLeftMouseDown &&
                                     (now - leftDownTime <= chordWindow) &&
                                     CGEventSource.buttonState(.combinedSessionState, button: .left) &&
                                     (hypot(loc.x - leftDownLocation.x, loc.y - leftDownLocation.y) <= maxChordDrift)
            isRightMouseDown = true
            rightDownTime = now
            rightDownLocation = loc

            if leftPhysicallyDown {
                chordTriggered = true
                chordTriggerTime = now
                // Left mouseDown already leaked to the active app milliseconds ago -> immediately send synthetic leftMouseUp
                // so the app cleanly ends selection/dragging and never gets stuck!
                postSyntheticMouseUp(button: .left, location: leftDownLocation)
                triggerMissionControl()
                return nil // Swallow rightMouseDown
            } else {
                // Fresh single right click: ensure any stale chord state is cleared so its rightMouseUp is never swallowed
                chordTriggered = false
                isLeftMouseDown = false
            }

        case .leftMouseDragged, .rightMouseDragged:
            if chordTriggered {
                if now - chordTriggerTime <= 1.5 {
                    return nil // Swallow phantom drag events while user is releasing the chord
                } else {
                    chordTriggered = false
                }
            }

        case .leftMouseUp:
            isLeftMouseDown = false
            if chordTriggered {
                let rightStillHeld = isRightMouseDown &&
                                     (now - chordTriggerTime <= 1.2) &&
                                     CGEventSource.buttonState(.combinedSessionState, button: .right)
                if !rightStillHeld {
                    isRightMouseDown = false
                    chordTriggered = false
                }
                return nil
            }

        case .rightMouseUp:
            isRightMouseDown = false
            if chordTriggered {
                let leftStillHeld = isLeftMouseDown &&
                                    (now - chordTriggerTime <= 1.2) &&
                                    CGEventSource.buttonState(.combinedSessionState, button: .left)
                if !leftStillHeld {
                    isLeftMouseDown = false
                    chordTriggered = false
                }
                return nil
            }

        default:
            break
        }
    }

    // 3. AltTab Window Switching (Command + Tab or Option + Tab)
    if gIsAltTabEnabled {
        if type == .flagsChanged {
            let flags = event.flags
            if let activeMask = gActiveModifierMask {
                let isStillHeld: Bool
                if activeMask == .maskCommand {
                    isStillHeld = flags.contains(.maskCommand)
                } else if activeMask == .maskAlternate {
                    isStillHeld = flags.contains(.maskAlternate)
                } else {
                    isStillHeld = false
                }

                if !isStillHeld {
                    gActiveModifierMask = nil
                    if gIsAltTabVisible {
                        gIsAltTabVisible = false
                        DispatchQueue.main.async {
                            WindowManager.shared.handleModifierReleased()
                        }
                    }
                }
            }
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Check triggers: Command + Tab or Option + Tab
            let isCmdTab = flags.contains(.maskCommand) && keyCode == 48
            let isOptTab = flags.contains(.maskAlternate) && keyCode == 48

            if isCmdTab || isOptTab {
                gActiveModifierMask = isCmdTab ? .maskCommand : .maskAlternate
                let isShift = flags.contains(.maskShift)
                gIsAltTabVisible = true
                DispatchQueue.main.async {
                    WindowManager.shared.handleShortcut(isShift: isShift)
                }
                return nil // Swallow Tab key event so native switcher never triggers
            }

            // Keyboard navigation when AltTab HUD is active
            if gIsAltTabVisible {
                if keyCode == 53 { // Esc
                    gIsAltTabVisible = false
                    gActiveModifierMask = nil
                    DispatchQueue.main.async {
                        WindowManager.shared.cancel()
                    }
                    return nil
                } else if keyCode == 50 { // ` or ~ (Tilde) -> cycle backward
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 123 { // Left Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 124 { // Right Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectNext()
                    }
                    return nil
                } else if keyCode == 126 { // Up Arrow -> Move to row above
                    DispatchQueue.main.async {
                        WindowManager.shared.selectUp()
                    }
                    return nil
                } else if keyCode == 125 { // Down Arrow -> Move to row below
                    DispatchQueue.main.async {
                        WindowManager.shared.selectDown()
                    }
                    return nil
                } else if keyCode == 13 { // W key (Close window)
                    DispatchQueue.main.async {
                        WindowManager.shared.closeSelectedWindow()
                    }
                    return nil
                } else if keyCode == 12 { // Q key (Quit app)
                    DispatchQueue.main.async {
                        WindowManager.shared.quitSelectedApp()
                    }
                    return nil
                }
            }
        }
    }

    // 4. Media Keys (Brightness UP/DOWN F1/F2)
    if type.rawValue == NX_SYSDEFINED {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        if nsEvent.subtype.rawValue == 8 {
            let data1 = nsEvent.data1
            let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = (data1 & 0x0000FFFF)
            let keyState = (((keyFlags & 0xFF00) >> 8)) == 0x0A

            if keyState && (keyCode == NX_KEYTYPE_BRIGHTNESS_UP || keyCode == NX_KEYTYPE_BRIGHTNESS_DOWN) {
                // If cursor-based brightness is disabled, do NOT intercept! Pass through to macOS native.
                if !gIsCursorBasedBrightnessEnabled {
                    return Unmanaged.passUnretained(event)
                }
                let isUp = (keyCode == NX_KEYTYPE_BRIGHTNESS_UP)
                DispatchQueue.main.async {
                    _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
                }
                // Return nil if external monitor was targeted or pass to macOS
                return nil
            }
        }
    }

    // 5. Spacebar tracking for Screenshot Mode (Holding Space to Move Selection)
    if type == .keyDown || type == .keyUp {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == 49 { // Space
            let isDown = (type == .keyDown)
            if gIsSpacePressed != isDown {
                gIsSpacePressed = isDown
                DispatchQueue.main.async {
                    ScreenshotManager.shared.isSpaceHeld = isDown
                }
            }
            if gIsScreenshotActive {
                return nil // Swallow Space in screenshot mode
            }
        }
    }

    // 6. Standard F1/F2 KeyDowns & Window Snapping
    if type == .keyDown {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Screenshot Active Hotkeys (LightShot Mode: Esc to cancel, ⌘C to copy, ⌘V/⌘S to save, ⌘Z to undo)
        if gIsScreenshotActive {
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)
            let hasAlt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Esc (keycode 53) -> Cancel capture
            if keycode == 53 && !hasCmd && !hasCtrl && !hasAlt && !hasShift {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.cancelCapture()
                }
                return nil
            }

            // ⌘C (keycode 8) -> Copy high-res cropped screenshot to clipboard
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 8 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.copyToClipboard()
                }
                return nil
            }

            // ⌘V (keycode 9) -> Save high-res screenshot to Downloads/Screenshots
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 9 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.saveToDownloads()
                }
                return nil
            }

            // ⌘S (keycode 1) -> Save high-res screenshot to Downloads/Screenshots
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 1 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.saveToDownloads()
                }
                return nil
            }

            // ⌘Z (keycode 6) -> Undo last stroke
            if hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 6 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.undoLastStroke()
                }
                return nil
            }

            // Tab (keycode 48) -> Switch to next screen if multiple displays connected
            if !hasCmd && !hasCtrl && !hasAlt && !hasShift && keycode == 48 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.switchScreen()
                }
                return nil
            }

            // In screenshot mode, swallow all other bare typing to prevent accidental shortcuts
            return nil
        }

        // Screenshot Trigger: ⌘⇧1 (Command + Shift + 1, keycode 18) or bare F4 (keycode 118 or 131)
        if gIsScreenshotEnabled && !gIsScreenshotActive {
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)
            let hasAlt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Primary: ⌘⇧1 (HyperMac LightShot - Leaves ⌘⇧4 untouched for macOS default)
            if hasCmd && hasShift && !hasCtrl && !hasAlt && keycode == 18 {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.startCapture()
                }
                return nil
            }

            // Secondary: bare F4
            if !hasCmd && !hasShift && !hasCtrl && !hasAlt && (keycode == 118 || keycode == 131) {
                DispatchQueue.main.async {
                    ScreenshotManager.shared.startCapture()
                }
                return nil
            }
        }

        // F1/F2 Brightness
        if keycode == 145 || keycode == 120 || keycode == 144 || keycode == 122 {
            // If cursor-based brightness is disabled, do NOT intercept! Pass through to macOS native.
            if !gIsCursorBasedBrightnessEnabled {
                return Unmanaged.passUnretained(event)
            }
            let isUp = (keycode == 145 || keycode == 120)
            DispatchQueue.main.async {
                _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
            }
            return nil
        }

        // Finder Cut & Paste (Windows-style ⌘X ➔ ⌘V)
        if gIsFinderCutPasteEnabled {
            let hasCmd = flags.contains(.maskCommand)
            let hasCtrl = flags.contains(.maskControl)
            let hasAlt = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Esc (keycode 53) -> Cancel pending cut in Finder
            if keycode == 53 && gIsFinderCutActive && !hasCmd && !hasCtrl && !hasAlt {
                if FinderCutPasteManager.isFinderFrontmost() {
                    DispatchQueue.main.async {
                        FinderCutPasteManager.shared.cancelCut(quiet: false)
                    }
                    return nil
                }
            }

            // Command-only shortcuts (no Option, no Control, no Shift)
            if hasCmd && !hasCtrl && !hasAlt && !hasShift {
                // ⌘X (keycode 7) -> Cut file(s) in Finder
                if keycode == 7 {
                    if FinderCutPasteManager.isFinderFrontmost() {
                        if !FinderCutPasteManager.isFinderEditingText() {
                            DispatchQueue.main.async {
                                FinderCutPasteManager.shared.triggerCut()
                            }
                            return nil // Swallow ⌘X so macOS doesn't beep
                        }
                    }
                }

                // ⌘V (keycode 9) -> Paste/Move cut file(s) in Finder
                if keycode == 9 && gIsFinderCutActive {
                    if FinderCutPasteManager.isFinderFrontmost() {
                        if !FinderCutPasteManager.isFinderEditingText() {
                            DispatchQueue.main.async {
                                FinderCutPasteManager.shared.triggerPaste()
                            }
                            return nil // Swallow ⌘V
                        }
                    }
                }

                // ⌘C (keycode 8) -> Manual copy cancels any cut state
                if keycode == 8 && gIsFinderCutActive {
                    DispatchQueue.main.async {
                        FinderCutPasteManager.shared.cancelCut(quiet: true)
                    }
                }
            }
        }

        // Bất kỳ ⌘C (8) hoặc ⌘X (7) đi qua hệ thống -> kích quick check ClipboardManager (60-300ms)
        if gIsClipboardEnabled &&
            flags.contains(.maskCommand) &&
            !flags.contains(.maskControl) &&
            !flags.contains(.maskAlternate) &&
            (keycode == 8 || keycode == 7) {
            DispatchQueue.main.async {
                ClipboardManager.shared.scheduleQuickCheck()
            }
        }

        // Command + Shift + (C or V) -> Toggle Clipboard Manager HUD (Maccy Replacement)
        let isCmdShift = flags.contains(.maskCommand) && flags.contains(.maskShift) && !flags.contains(.maskControl)
        if gIsClipboardEnabled && isCmdShift && keycode == gClipboardShortcutKeycode {
            DispatchQueue.main.async {
                ClipboardManager.shared.toggleHUD()
            }
            return nil
        }

        // Clipboard HUD Active Keys
        if gIsClipboardHUDVisible {
            let hasCommand = flags.contains(.maskCommand)
            let hasControl = flags.contains(.maskControl)
            let hasOption = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)

            // Command + Up/Down (⌘↑ / ⌘↓) -> Reorder selected pinned item
            if hasCommand && !hasControl && !hasOption && !hasShift {
                if keycode == 126 { // Up Arrow (⌘↑)
                    DispatchQueue.main.async {
                        ClipboardManager.shared.moveSelectedPinned(direction: .up)
                    }
                    return nil
                } else if keycode == 125 { // Down Arrow (⌘↓)
                    DispatchQueue.main.async {
                        ClipboardManager.shared.moveSelectedPinned(direction: .down)
                    }
                    return nil
                }
            }

            // Let system-level shortcuts (⌘C, ⌘V, ⌘A...) pass through untouched.
            if !hasCommand && !hasControl {
                if keycode == 53 { // Esc -> Close HUD
                    gIsClipboardHUDVisible = false
                    DispatchQueue.main.async {
                        ClipboardManager.shared.hideHUD()
                    }
                    return nil
                } else if keycode == 126 { // Up Arrow -> previous clip
                    DispatchQueue.main.async {
                        ClipboardManager.shared.selectPrevious()
                    }
                    return nil
                } else if keycode == 125 { // Down Arrow -> next clip
                    DispatchQueue.main.async {
                        ClipboardManager.shared.selectNext()
                    }
                    return nil
                } else if keycode == 36 || keycode == 76 { // Return / Numpad Enter -> paste selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.pasteSelectedItem()
                    }
                    return nil
                } else if hasOption && keycode == 35 { // ⌥P -> pin / unpin selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.togglePinSelected()
                    }
                    return nil
                } else if hasOption && (keycode == 51 || keycode == 117) { // ⌥⌫ -> delete selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.deleteSelectedItem()
                    }
                    return nil
                } else if !hasOption && !flags.contains(.maskShift) && gIsClipboardSearchEmpty,
                          let index = clipboardQuickPasteIndex(for: keycode) { // 1...9 -> instant paste
                    DispatchQueue.main.async {
                        ClipboardManager.shared.pasteItemAt(index: index)
                    }
                    return nil
                }
            }
        }

        // Option + Control shortcuts -> Window Snapping (Rectangle-style)
        let isOptCtrl = flags.contains(.maskAlternate) && flags.contains(.maskControl) && !flags.contains(.maskCommand)
        if isOptCtrl {
            let now = Date().timeIntervalSince1970
            let chordWindow: TimeInterval = 0.65

            // 1. Return / Numpad Enter -> Maximize
            if keycode == 36 || keycode == 76 {
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.maximize) }
                return nil
            }

            // 2. C (Keycode 8) or Delete / Forward Delete -> Center
            if keycode == 8 || keycode == 51 || keycode == 117 {
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.center) }
                return nil
            }

            // 3. Direct 4-corner keys: U / I / J / K and Numpad 7 / 9 / 1 / 3
            if keycode == 32 || keycode == 89 { // U or Num7 -> Top Left (Trái Trên)
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.topLeft) }
                return nil
            }
            if keycode == 34 || keycode == 92 { // I or Num9 -> Top Right (Phải Trên)
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.topRight) }
                return nil
            }
            if keycode == 38 || keycode == 83 { // J or Num1 -> Bottom Left (Trái Dưới)
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.bottomLeft) }
                return nil
            }
            if keycode == 40 || keycode == 85 { // K or Num3 -> Bottom Right (Phải Dưới)
                gLastSnapArrowKey = 0
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.bottomRight) }
                return nil
            }

            // 4. Arrow keys (123: Left, 124: Right, 125: Down, 126: Up)
            if keycode >= 123 && keycode <= 126 {
                // Check if this forms a 4-corner combo with the previous arrow key
                if (now - gLastSnapArrowTime) <= chordWindow && gLastSnapArrowKey != 0 && gLastSnapArrowKey != keycode {
                    let prev = gLastSnapArrowKey
                    // Left (123) + Up (126) -> Top Left (Trái Trên)
                    if (prev == 123 && keycode == 126) || (prev == 126 && keycode == 123) {
                        gLastSnapArrowKey = 0
                        DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.topLeft) }
                        return nil
                    }
                    // Left (123) + Down (125) -> Bottom Left (Trái Dưới)
                    if (prev == 123 && keycode == 125) || (prev == 125 && keycode == 123) {
                        gLastSnapArrowKey = 0
                        DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.bottomLeft) }
                        return nil
                    }
                    // Right (124) + Up (126) -> Top Right (Phải Trên)
                    if (prev == 124 && keycode == 126) || (prev == 126 && keycode == 124) {
                        gLastSnapArrowKey = 0
                        DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.topRight) }
                        return nil
                    }
                    // Right (124) + Down (125) -> Bottom Right (Phải Dưới)
                    if (prev == 124 && keycode == 125) || (prev == 125 && keycode == 124) {
                        gLastSnapArrowKey = 0
                        DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.bottomRight) }
                        return nil
                    }
                }

                // Single arrow press (or first arrow of a combination)
                gLastSnapArrowKey = keycode
                gLastSnapArrowTime = now

                switch keycode {
                case 123: // Left Arrow -> Left Half
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.leftHalf) }
                    return nil
                case 124: // Right Arrow -> Right Half
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.rightHalf) }
                    return nil
                case 126: // Up Arrow -> Top Half
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.topHalf) }
                    return nil
                case 125: // Down Arrow -> Bottom Half
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.bottomHalf) }
                    return nil
                default:
                    break
                }
            }
        }

        // Option + Command + Arrow keys (or Ctrl + Option + Command + Arrow keys - Rectangle standard)
        // -> Move to Display (Next / Previous)
        let isNextPrevDisplay = flags.contains(.maskAlternate) && flags.contains(.maskCommand)
        if isNextPrevDisplay {
            switch keycode {
            case 124, 126: // Right or Up Arrow -> Next Display
                appLog("⌨️ Shortcut: Move Window to Next Display")
                DispatchQueue.main.async { WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: true) }
                return nil
            case 123, 125: // Left or Down Arrow -> Previous Display
                appLog("⌨️ Shortcut: Move Window to Previous Display")
                DispatchQueue.main.async { WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: false) }
                return nil
            case 11: // 'B' Key -> Toggle Menu Bar Hider (⌘⌥B)
                if gIsMenuBarHiderEnabled {
                    appLog("⌨️ Shortcut: Toggle Menu Bar Hider (⌘⌥B)")
                    DispatchQueue.main.async { MenuBarHiderManager.shared.toggle() }
                    return nil
                }
            default:
                break
            }
        }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - KeyInterceptor Singleton

@MainActor
public class KeyInterceptor {
    public static let shared = KeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var currentTap: CFMachPort? {
        return eventTap
    }

    private init() {}

    public func updateSettings() {
        gIsMouseChordEnabled = (UserDefaults.standard.object(forKey: "mouse_chord_enabled") as? Bool) ?? true
        gIsAltTabEnabled = (UserDefaults.standard.object(forKey: "alttab_enabled") as? Bool) ?? true
        gIsClipboardEnabled = (UserDefaults.standard.object(forKey: "clipboard_monitoring_enabled") as? Bool) ?? true
        gIsFinderCutPasteEnabled = (UserDefaults.standard.object(forKey: "finder_cut_paste_enabled") as? Bool) ?? true
        let shortcut = UserDefaults.standard.string(forKey: "clipboard_hud_shortcut") ?? "cmd_shift_c"
        gClipboardShortcutKeycode = (shortcut == "cmd_shift_v") ? 9 : 8
        gIsCursorBasedBrightnessEnabled = (UserDefaults.standard.object(forKey: "cursor_based_brightness") as? Bool) ?? true
        gIsScreenshotEnabled = (UserDefaults.standard.object(forKey: "screenshot_enabled") as? Bool) ?? true
    }

    public func start() {
        guard eventTap == nil else { return }

        updateSettings()

        // Listen for Media Keys, KeyDowns, KeyUps, FlagsChanged, and Mouse Left/Right (Down, Up, Dragged)
        let keyMask: UInt64 = (UInt64(1) << UInt64(NX_SYSDEFINED)) |
                              (UInt64(1) << UInt64(CGEventType.keyDown.rawValue)) |
                              (UInt64(1) << UInt64(CGEventType.keyUp.rawValue)) |
                              (UInt64(1) << UInt64(CGEventType.flagsChanged.rawValue))
        let mouseMask: UInt64 = (UInt64(1) << UInt64(CGEventType.leftMouseDown.rawValue)) |
                                (UInt64(1) << UInt64(CGEventType.leftMouseUp.rawValue)) |
                                (UInt64(1) << UInt64(CGEventType.leftMouseDragged.rawValue)) |
                                (UInt64(1) << UInt64(CGEventType.rightMouseDown.rawValue)) |
                                (UInt64(1) << UInt64(CGEventType.rightMouseUp.rawValue)) |
                                (UInt64(1) << UInt64(CGEventType.rightMouseDragged.rawValue))
        let mask: UInt64 = keyMask | mouseMask

        // EXCLUSIVELY use .cgSessionEventTap for user-session safety!
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: nil
        )

        guard let validTap = tap else {
            let trusted = AXIsProcessTrusted()
            appLog("⚠️ KeyInterceptor: Could not create session CGEventTap. AXIsProcessTrusted=\(trusted). Retrying in 1.5s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.start()
            }
            return
        }

        self.eventTap = validTap
        gCurrentTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        appLog("✅ KeyInterceptor: Active on Session level (Safe, no deadlocks).")
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
            gCurrentTap = nil
            appLog("⏹ KeyInterceptor stopped.")
        }
    }
}
