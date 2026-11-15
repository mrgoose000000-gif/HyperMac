// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon
import Combine

struct ShortcutBinding: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt64
    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    init(_ keyCode: UInt16, _ flags: CGEventFlags) {
        self.keyCode = keyCode == 131 ? 118 : keyCode // Some keyboards report F4 as 131.
        self.modifiers = flags.intersection(Self.modifierMask).rawValue
    }
    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    var holdFlags: CGEventFlags { flags.subtracting(.maskShift) }
    var title: String {
        let prefix = [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
            .filter { flags.contains($0.0) }.map { $0.1 }.joined()
        return prefix + Self.keyName(keyCode)
    }
    static let functionKeys: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
    static func keyName(_ code: UInt16) -> String {
        let special: [UInt16: String] = [36:"↩",48:"Tab",49:"Space",51:"⌫",53:"Esc",76:"Num ↩",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"PgUp",121:"PgDn",71:"Clear"]
        if let name = special[code] ?? functionKeys[code] { return name }
        // Resolve physical keycodes using the active ASCII-capable keyboard layout.
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0, length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            if UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars) == noErr, length > 0 {
                let label = String(utf16CodeUnits: chars, count: length).uppercased()
                return (65...92).contains(code) ? "Num " + label : label
            }
        }
        return "Key \(code)"
    }
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case screenshot, clipboard, switchWindows
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, restoreWindow
    case topLeft, topRight, bottomLeft, bottomRight
    case nextDisplay, previousDisplay, restorePrimaryDisplay, menuBar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .screenshot: return tr("Chụp màn hình", "Screenshot")
        case .clipboard: return tr("Mở Clipboard", "Open Clipboard")
        case .switchWindows: return tr("Chuyển cửa sổ", "Switch windows")
        case .leftHalf: return tr("Nửa trái", "Left half")
        case .rightHalf: return tr("Nửa phải", "Right half")
        case .topHalf: return tr("Nửa trên", "Top half")
        case .bottomHalf: return tr("Nửa dưới", "Bottom half")
        case .maximize: return tr("Phóng to cửa sổ", "Maximize window")
        case .center: return tr("Căn giữa", "Center")
        case .restoreWindow: return tr("Khôi phục kích thước", "Restore window size")
        case .topLeft: return tr("Góc trên trái", "Top left")
        case .topRight: return tr("Góc trên phải", "Top right")
        case .bottomLeft: return tr("Góc dưới trái", "Bottom left")
        case .bottomRight: return tr("Góc dưới phải", "Bottom right")
        case .nextDisplay: return tr("Sang màn hình tiếp", "Next display")
        case .previousDisplay: return tr("Sang màn hình trước", "Previous display")
        case .restorePrimaryDisplay: return tr("Mở màn hình chính", "Turn on built-in screen")
        case .menuBar: return tr("Ngăn kéo Menu Bar", "Menu Bar drawer")
        }
    }
    var defaults: [ShortcutBinding] {
        let co: CGEventFlags = [.maskControl, .maskAlternate]
        let oc: CGEventFlags = [.maskAlternate, .maskCommand]
        switch self {
        case .screenshot: return [.init(18, [.maskCommand, .maskShift]), .init(118, [])]
        case .clipboard: return [.init(8, [.maskCommand, .maskShift])]
        case .switchWindows: return [.init(48, .maskCommand), .init(48, .maskAlternate)]
        case .leftHalf: return [.init(123, co)]
        case .rightHalf: return [.init(124, co)]
        case .topHalf: return [.init(126, co)]
        case .bottomHalf: return [.init(125, co)]
        case .maximize: return [36,76].map { .init($0, co) }
        case .center: return [.init(8, co)]
        case .restoreWindow: return [.init(51, co)]
        case .topLeft: return [32,89].map { .init($0, co) }
        case .topRight: return [34,92].map { .init($0, co) }
        case .bottomLeft: return [38,83].map { .init($0, co) }
        case .bottomRight: return [40,85].map { .init($0, co) }
        case .nextDisplay: return [124,126].flatMap { [ShortcutBinding($0, oc), .init($0, oc.union(.maskControl))] }
        case .previousDisplay: return [123,125].flatMap { [ShortcutBinding($0, oc), .init($0, oc.union(.maskControl))] }
        case .restorePrimaryDisplay: return [.init(18, [.maskControl, .maskAlternate, .maskCommand])] // ⌃⌥⌘1
        case .menuBar: return [.init(11, oc)]
        }
    }
    var snapAction: SnapAction? {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        case .maximize: return .maximize
        case .center: return .center
        case .restoreWindow: return .restore
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        default: return nil
        }
    }
}

struct ShortcutMatch {
    let action: ShortcutAction
    let binding: ShortcutBinding
    let reversed: Bool
}

struct ShortcutConfiguration {
    var bindings: [ShortcutAction: [ShortcutBinding]] = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaults) })
    func match(_ key: UInt16, flags: CGEventFlags) -> ShortcutMatch? {
        let input = ShortcutBinding(key, flags)
        for action in ShortcutAction.allCases {
            for binding in bindings[action] ?? [] {
                if input == binding { return .init(action: action, binding: binding, reversed: false) }
                if action == .switchWindows && input.keyCode == binding.keyCode && input.flags == binding.flags.union(.maskShift) {
                    return .init(action: action, binding: binding, reversed: true)
                }
            }
        }
        return nil
    }
    // Preserve the old two-arrow quarter gesture only while its component bindings remain defaults.
    var usesDefaultArrowChords: Bool {
        [ShortcutAction.leftHalf, .rightHalf, .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight]
            .allSatisfy { bindings[$0] == $0.defaults }
    }
    func conflict(for candidate: ShortcutBinding, action: ShortcutAction, replacing index: Int?) -> ShortcutAction? {
        let candidates = action == .switchWindows ? [candidate, .init(candidate.keyCode, candidate.flags.union(.maskShift))] : [candidate]
        for other in ShortcutAction.allCases {
            for (offset, existing) in (bindings[other] ?? []).enumerated() {
                if other == action && offset == index { continue }
                let occupied = other == .switchWindows ? [existing, .init(existing.keyCode, existing.flags.union(.maskShift))] : [existing]
                if candidates.contains(where: occupied.contains) { return other }
            }
        }
        return nil
    }
    static func invalidReason(_ binding: ShortcutBinding, action: ShortcutAction) -> String? {
        if binding.keyCode > 126 || [54,55,56,57,58,59,60,61,62,63].contains(binding.keyCode) {
            return tr("Chọn một phím cùng tổ hợp bổ trợ.", "Choose a key with modifiers.")
        }
        if action == .switchWindows && (binding.holdFlags.isEmpty || binding.flags.contains(.maskShift)) {
            return tr("Dùng ⌘, ⌥ hoặc ⌃ và một phím; giữ Shift để chuyển ngược.", "Use ⌘, ⌥ or ⌃ with a key; Shift is reserved for reverse cycling.")
        }
        if binding.holdFlags.isEmpty && functionKeysWithoutModifiers(binding) == false {
            return tr("Cần thêm ⌘, ⌥ hoặc ⌃ để không chặn thao tác gõ chữ.", "Add ⌘, ⌥ or ⌃ so normal typing remains available.")
        }
        if binding.flags.isEmpty && [122,120].contains(binding.keyCode) {
            return tr("F1/F2 đang dành cho độ sáng. Hãy thêm phím bổ trợ.", "F1/F2 are used for brightness. Add a modifier.")
        }
        if binding.flags == .maskCommand && [0,1,6,7,8,9,12,13,4,46].contains(binding.keyCode) {
            return tr("Tổ hợp này dành cho thao tác chuẩn của ứng dụng. Chọn tổ hợp khác.", "This is a standard application shortcut. Choose another combination.")
        }
        if binding == .init(53, [.maskCommand, .maskAlternate]) || binding == .init(12, [.maskCommand, .maskControl]) {
            return tr("Tổ hợp này dành cho chức năng hệ thống.", "This combination is reserved by the system.")
        }
        return nil
    }
    private static func functionKeysWithoutModifiers(_ binding: ShortcutBinding) -> Bool {
        ShortcutBinding.functionKeys[binding.keyCode] != nil
    }
    static func systemWarning(_ binding: ShortcutBinding) -> String? {
        if (binding.keyCode == 48 && binding.flags.contains(.maskCommand)) ||
            (binding.keyCode == 49 && !binding.holdFlags.isEmpty) ||
            ([20,21,23].contains(binding.keyCode) && binding.flags == [.maskCommand, .maskShift]) ||
            ([123,124,125,126].contains(binding.keyCode) && binding.flags == .maskControl) ||
            (binding.flags.isEmpty && ShortcutBinding.functionKeys[binding.keyCode] != nil) {
            return tr("Có thể trùng phím macOS. Khi HyperMac nhận phím này, chức năng hệ thống có thể bị thay thế.",
                      "May conflict with macOS. When HyperMac handles this key, the system action may be replaced.")
        }
        return nil
    }
}

// Both the session event tap and UI updates run on the main run loop. This snapshot
// avoids actor hops, UserDefaults reads and blocking operations inside the event tap.
var gShortcutConfiguration = ShortcutConfiguration()
var gIsRecordingShortcut = false
var gIsWindowSnapEnabled = true

@MainActor
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    @Published var settingsMessage: String?
    @Published private(set) var configuration: ShortcutConfiguration
    private let defaults: UserDefaults
    private let publishRuntime: Bool
    static let preferencesKey = "hypermac_shortcuts_v1"
    init(defaults: UserDefaults = .standard, publishRuntime: Bool = true) {
        self.defaults = defaults
        self.publishRuntime = publishRuntime
        var loaded = ShortcutConfiguration()
        if defaults.string(forKey: "clipboard_hud_shortcut") == "cmd_shift_v" {
            loaded.bindings[.clipboard] = [.init(9, [.maskCommand, .maskShift])]
        }
        if let data = defaults.data(forKey: Self.preferencesKey),
            let saved = try? JSONDecoder().decode([String: [ShortcutBinding]].self, from: data) {
            var candidate = loaded
            for action in ShortcutAction.allCases {
                if let values = saved[action.rawValue], values.allSatisfy({ ShortcutConfiguration.invalidReason($0, action: action) == nil }) {
                    candidate.bindings[action] = values
                }
            }
            if saved[ShortcutAction.restoreWindow.rawValue] == nil {
                // Upgrade the old Center aliases without resetting unrelated custom bindings.
                let co: CGEventFlags = [.maskControl, .maskAlternate]
                let oldDefaults = [8,51,117].map { ShortcutBinding(UInt16($0), co) }
                if Set(candidate.bindings[.center] ?? []) == Set(oldDefaults) {
                    candidate.bindings[.center] = ShortcutAction.center.defaults
                } else {
                    candidate.bindings[.center]?.removeAll { $0 == ShortcutBinding(51, co) }
                }
                candidate.bindings[.restoreWindow] = []
                let restore = ShortcutBinding(51, co)
                if candidate.conflict(for: restore, action: .restoreWindow, replacing: nil) == nil {
                    candidate.bindings[.restoreWindow] = [restore]
                }
            }
            let valid = ShortcutAction.allCases.allSatisfy { action in
                (candidate.bindings[action] ?? []).enumerated().allSatisfy {
                    candidate.conflict(for: $0.element, action: action, replacing: $0.offset) == nil
                }
            }
            if valid {
                loaded = candidate
                if saved[ShortcutAction.restoreWindow.rawValue] == nil {
                    let updated = Dictionary(uniqueKeysWithValues: candidate.bindings.map { ($0.key.rawValue, $0.value) })
                    if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: Self.preferencesKey) }
                }
            }
        }
        configuration = loaded
        if publishRuntime { gShortcutConfiguration = loaded }
    }
    func title(_ action: ShortcutAction) -> String {
        let values = configuration.bindings[action] ?? []
        return values.isEmpty ? tr("Đã tắt", "Disabled") : values.map(\.title).joined(separator: " / ")
    }
    func primaryTitle(_ action: ShortcutAction) -> String {
        configuration.bindings[action]?.first?.title ?? tr("Đã tắt", "Disabled")
    }
    func error(for binding: ShortcutBinding, action: ShortcutAction, index: Int?) -> String? {
        if let reason = ShortcutConfiguration.invalidReason(binding, action: action) { return reason }
        if let other = configuration.conflict(for: binding, action: action, replacing: index) {
            return tr("Trùng với: \(other.title). Hãy đổi hoặc xóa tổ hợp đó trước.", "Already used by: \(other.title). Change or remove it first.")
        }
        return nil
    }
    @discardableResult func set(_ binding: ShortcutBinding, action: ShortcutAction, index: Int?) -> String? {
        if let error = error(for: binding, action: action, index: index) { return error }
        var list = configuration.bindings[action] ?? []
        if let index {
            guard list.indices.contains(index) else { return tr("Tổ hợp đã thay đổi. Vui lòng thử lại.", "Binding changed. Please try again.") }
            list[index] = binding
        } else { list.append(binding) }
        configuration.bindings[action] = list
        persist()
        return nil
    }
    func remove(_ action: ShortcutAction, index: Int) {
        guard configuration.bindings[action]?.indices.contains(index) == true else { return }
        configuration.bindings[action]?.remove(at: index)
        persist()
    }
    func disable(_ action: ShortcutAction) { configuration.bindings[action] = []; persist() }
    @discardableResult func restore(_ action: ShortcutAction) -> String? {
        var proposed = configuration
        proposed.bindings[action] = []
        for binding in action.defaults {
            if let other = proposed.conflict(for: binding, action: action, replacing: nil) {
                return tr("Phím mặc định đang được dùng bởi \(other.title).", "Default shortcut is in use by \(other.title).")
            }
        }
        configuration.bindings[action] = action.defaults
        persist()
        return nil
    }
    func restoreAll() { configuration = ShortcutConfiguration(); persist() }
    private func persist() {
        let saved = Dictionary(uniqueKeysWithValues: configuration.bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.preferencesKey) }
        if publishRuntime {
            gShortcutConfiguration = configuration
            NotificationCenter.default.post(name: .hypermacShortcutsChanged, object: nil)
        }
    }
    func perform(_ action: ShortcutAction) {
        if let snap = action.snapAction { WindowSnapManager.shared.snapActiveWindow(snap); return }
        switch action {
        case .screenshot: ScreenshotManager.shared.startCapture()
        case .clipboard: ClipboardManager.shared.toggleHUD()
        case .nextDisplay: WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: true)
        case .previousDisplay: WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: false)
        case .restorePrimaryDisplay: DisplayManager.shared.restorePrimaryDisplay()
        case .menuBar: MenuBarHiderManager.shared.toggle()
        default: break
        }
    }
}
extension Notification.Name {
    static let hypermacShortcutsChanged = Notification.Name("HyperMacShortcutsChanged")
}
