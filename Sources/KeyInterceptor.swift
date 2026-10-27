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

// Fast lock-free flags for eventTapCallback
public var gIsMouseChordEnabled: Bool = true
public var gIsAltTabEnabled: Bool = true
public var gIsAltTabVisible: Bool = false
public var gIsClipboardEnabled: Bool = true
public var gIsClipboardHUDVisible: Bool = false
private var gActiveModifierMask: CGEventFlags? = nil
private var gCurrentTap: CFMachPort? = nil

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

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // 1. Safety handler for system tap disable
    if type == .tapDisabledByUserInput {
        // User revoked permission in System Settings -> STOP cleanly! Do NOT fight WindowServer!
        appLog("⚠️ EventTap was disabled by user/system in Accessibility settings. Stopping.")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                KeyInterceptor.shared.stop()
            }
        }
        return Unmanaged.passRetained(event)
    }

    if type == .tapDisabledByTimeout {
        // Timeout from macOS -> Re-enable safely
        if let tap = gCurrentTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    // 2. Mouse Chording: Simultaneous Left + Right Click -> F3 (Mission Control)
    if gIsMouseChordEnabled {
        let now = Date().timeIntervalSince1970
        let chordWindow: TimeInterval = 0.5

        switch type {
        case .leftMouseDown:
            isLeftMouseDown = true
            leftDownTime = now
            if isRightMouseDown && (now - rightDownTime <= chordWindow) {
                chordTriggered = true
                triggerMissionControl()
                return nil // Swallow left click
            }

        case .rightMouseDown:
            isRightMouseDown = true
            rightDownTime = now
            if isLeftMouseDown && (now - leftDownTime <= chordWindow) {
                chordTriggered = true
                triggerMissionControl()
                return nil // Swallow right click
            }

        case .leftMouseUp:
            isLeftMouseDown = false
            if chordTriggered {
                if !isRightMouseDown { chordTriggered = false }
                return nil
            }

        case .rightMouseUp:
            isRightMouseDown = false
            if chordTriggered {
                if !isLeftMouseDown { chordTriggered = false }
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
                            WindowManager.shared.commitSelection()
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
            return Unmanaged.passRetained(event)
        }

        if nsEvent.subtype.rawValue == 8 {
            let data1 = nsEvent.data1
            let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = (data1 & 0x0000FFFF)
            let keyState = (((keyFlags & 0xFF00) >> 8)) == 0x0A

            if keyState && (keyCode == NX_KEYTYPE_BRIGHTNESS_UP || keyCode == NX_KEYTYPE_BRIGHTNESS_DOWN) {
                let isUp = (keyCode == NX_KEYTYPE_BRIGHTNESS_UP)
                DispatchQueue.main.async {
                    _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
                }
                // Return nil if external monitor was targeted or pass to macOS
                return nil
            }
        }
    }

    // 5. Standard F1/F2 KeyDowns & Window Snapping
    if type == .keyDown {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // F1/F2 Brightness
        if keycode == 145 || keycode == 120 || keycode == 144 || keycode == 122 {
            let isUp = (keycode == 145 || keycode == 120)
            DispatchQueue.main.async {
                _ = DisplayManager.shared.handleBrightnessKey(isUp: isUp)
            }
            return nil
        }

        // Command + Shift + C (or Cmd + Shift + V) -> Toggle Clipboard Manager HUD (Maccy Replacement)
        let isCmdShift = flags.contains(.maskCommand) && flags.contains(.maskShift) && !flags.contains(.maskControl)
        if gIsClipboardEnabled && isCmdShift && (keycode == 8 || keycode == 9) {
            DispatchQueue.main.async {
                ClipboardManager.shared.toggleHUD()
            }
            return nil
        }

        // Clipboard HUD Active Keys
        if gIsClipboardHUDVisible {
            if keycode == 53 { // Esc -> Close HUD
                gIsClipboardHUDVisible = false
                DispatchQueue.main.async {
                    ClipboardManager.shared.hideHUD()
                }
                return nil
            }
        }

        // Option + Control + Arrow keys -> Window Snapping (Rectangle-style)
        let isOptCtrl = flags.contains(.maskAlternate) && flags.contains(.maskControl) && !flags.contains(.maskCommand)
        if isOptCtrl {
            switch keycode {
            case 123: // Left Arrow -> Left Half
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.leftHalf) }
                return nil
            case 124: // Right Arrow -> Right Half
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.rightHalf) }
                return nil
            case 126: // Up Arrow -> Maximize
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.maximize) }
                return nil
            case 125: // Down Arrow -> Center
                DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.center) }
                return nil
            default:
                break
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
            default:
                break
            }
        }
    }

    return Unmanaged.passRetained(event)
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
    }

    public func start() {
        guard eventTap == nil else { return }

        updateSettings()

        // Listen for Media Keys, KeyDowns, FlagsChanged, and Mouse Left/Right
        let mask: UInt64 = (1 << NX_SYSDEFINED) |
                           (1 << CGEventType.keyDown.rawValue) |
                           (1 << CGEventType.flagsChanged.rawValue) |
                           (1 << CGEventType.leftMouseDown.rawValue) |
                           (1 << CGEventType.leftMouseUp.rawValue) |
                           (1 << CGEventType.rightMouseDown.rawValue) |
                           (1 << CGEventType.rightMouseUp.rawValue)

        // EXCLUSIVELY use .cgSessionEventTap for user-session safety!
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
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
