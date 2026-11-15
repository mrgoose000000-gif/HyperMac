// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

// Hallmark · component: shortcut settings · genre: modern-minimal · theme: HyperMac native
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4
// Native focus/pressed/disabled states; recording, conflict, warning and saved states.
struct ShortcutSettingsCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Tự gán phím", "Customize shortcuts")).font(.system(size: FS.body, weight: .semibold))
                Text(tr("Đổi, thêm hoặc tắt từng tổ hợp phím", "Change, add or disable key combinations"))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(tr("Tùy chỉnh…", "Customize…")) { ShortcutSettingsWindow.shared.show() }
                .controlSize(.small)
        }.padding(10).cardBackground()
    }
}

@MainActor
final class ShortcutSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = ShortcutSettingsWindow()
    private var window: NSWindow?
    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = tr("Phím tắt HyperMac", "HyperMac shortcuts")
        window.contentMinSize = NSSize(width: 400, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ShortcutSettingsView(manager: .shared))
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { ShortcutRecorder.shared.cancel(); window = nil }
}

struct ShortcutSettingsView: View {
    @ObservedObject var manager: ShortcutManager
    private let groups: [(String, [ShortcutAction])] = [
        (tr("Mở chức năng", "Open features"), [.screenshot, .clipboard, .switchWindows, .menuBar]),
        (tr("Chia cửa sổ", "Arrange windows"), [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .center, .restoreWindow, .topLeft, .topRight, .bottomLeft, .bottomRight]),
        (tr("Màn hình", "Displays"), [.restorePrimaryDisplay, .nextDisplay, .previousDisplay])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Phím tắt của bạn", "Your shortcuts")).font(.system(size: FS.value, weight: .semibold))
            Text(tr("Bấm tổ hợp để đổi. Dấu + để thêm, × để xóa. Phím chỉ hoạt động khi chức năng tương ứng được bật.",
                    "Click a combination to change it. Use + to add, × to remove. Shortcuts work when their feature is enabled."))
                .font(.system(size: FS.body)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.0).font(.system(size: FS.title, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(group.1) { action in row(action) }
                        }
                    }
                    Text(tr("Chuyển cửa sổ: giữ phím bổ trợ, nhấn thêm Shift để chuyển ngược; thả phím bổ trợ để chọn. ⌘C, ⌘Z, Esc và phím thao tác trong trình chỉnh sửa vẫn giữ nguyên.",
                            "Window switching: hold modifiers, add Shift to cycle backward, release modifiers to select. ⌘C, ⌘Z, Esc and editor navigation stay unchanged."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(tr("HyperMac kiểm tra trùng phím nội bộ và cảnh báo một số phím macOS. Phím do ứng dụng khác đăng ký có thể vẫn trùng.",
                            "HyperMac checks its own bindings and warns about common macOS shortcuts. Other apps may still use the same keys."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.trailing, 4)
            }
            if let message = manager.settingsMessage { Text(message).font(.system(size: FS.body)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Text(tr("Lưu tự động", "Saved automatically")).font(.system(size: FS.caption)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Khôi phục tất cả", "Restore all defaults")) { manager.restoreAll(); manager.settingsMessage = nil }
                    .disabled(manager.configuration.bindings == ShortcutConfiguration().bindings)
            }
        }.padding(18).frame(minWidth: 360, minHeight: 360)
    }
    private func row(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title).font(.system(size: FS.body, weight: .medium))
                Spacer()
                Button { ShortcutRecorder.shared.begin(action, index: nil, manager: manager) } label: { Image(systemName: "plus") }
                    .help(tr("Thêm phím", "Add shortcut")).accessibilityLabel(tr("Thêm phím cho \(action.title)", "Add shortcut for \(action.title)"))
                Menu {
                    Button(tr("Tắt phím của chức năng này", "Disable shortcuts for this action")) { manager.disable(action); manager.settingsMessage = nil }
                    Button(tr("Khôi phục mặc định", "Restore defaults")) { manager.settingsMessage = manager.restore(action) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 22)
                .accessibilityLabel(tr("Tùy chọn \(action.title)", "Options for \(action.title)"))
            }
            let values = manager.configuration.bindings[action] ?? []
            if values.isEmpty {
                Text(tr("Đã tắt phím tắt", "Shortcut disabled")).font(.system(size: FS.caption)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, binding in
                        HStack(spacing: 2) {
                            Button(binding.title) { ShortcutRecorder.shared.begin(action, index: index, manager: manager) }
                                .font(.system(size: FS.body, weight: .medium, design: .monospaced))
                                .help(tr("Bấm để đổi phím", "Click to change shortcut"))
                                .accessibilityLabel("\(action.title): \(binding.title)")
                            Button { manager.remove(action, index: index); manager.settingsMessage = nil } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(tr("Xóa \(binding.title)", "Remove \(binding.title)"))
                        }.controlSize(.small)
                    }
                }
            }
            Divider()
        }
    }
}

@MainActor
final class ShortcutRecorder: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ShortcutRecorder()
    @Published private(set) var candidate: ShortcutBinding?
    @Published private(set) var error: String?
    @Published private(set) var action: ShortcutAction = .screenshot
    private var index: Int?
    private var manager: ShortcutManager?
    private var panel: NSPanel?
    private var monitor: Any?
    var warning: String? { candidate.flatMap(ShortcutConfiguration.systemWarning) }
    var canSave: Bool { candidate != nil && error == nil }
    func begin(_ action: ShortcutAction, index: Int?, manager: ShortcutManager) {
        cancel()
        self.action = action; self.index = index; self.manager = manager
        candidate = nil; error = nil
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 270),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = action.title
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShortcutRecorderView(recorder: self))
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        gIsRecordingShortcut = true
        // Fallback for local keyboard input if Accessibility/event tap is unavailable.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            self.receive(event.keyCode, flags: event.cgEvent?.flags ?? [], repeated: event.isARepeat)
            return nil
        }
    }
    func receive(_ code: UInt16, flags: CGEventFlags, repeated: Bool = false) {
        guard panel != nil, !repeated else { return }
        let binding = ShortcutBinding(code, flags)
        if code == 53 && binding.flags.isEmpty { cancel(); return }
        candidate = binding
        error = manager?.error(for: binding, action: action, index: index)
    }
    func save() {
        guard let candidate, canSave, let manager else { return }
        if let failure = manager.set(candidate, action: action, index: index) { error = failure; return }
        cancel()
    }
    func cancel() {
        gIsRecordingShortcut = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        let previous = panel
        panel = nil
        previous?.delegate = nil
        previous?.close()
        manager = nil
    }
    func windowWillClose(_ notification: Notification) { cancel() }
    func windowDidResignKey(_ notification: Notification) { cancel() }
}

struct ShortcutRecorderView: View {
    @ObservedObject var recorder: ShortcutRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Nhấn tổ hợp phím mới", "Press a new key combination"))
                .font(.system(size: FS.subhead, weight: .semibold))
            Text(recorder.candidate?.title ?? tr("Đang chờ phím…", "Waiting for keys…"))
                .font(.system(size: FS.display, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color.primary.opacity(0.06)))
            Text(recorder.error ?? recorder.warning ?? tr("Nhấn tổ hợp rồi bấm Lưu. Esc để hủy.", "Press a combination, then click Save. Esc cancels."))
                .font(.system(size: FS.body))
                .foregroundStyle(recorder.error != nil || recorder.warning != nil ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            HStack {
                Button(tr("Hủy", "Cancel")) { recorder.cancel() }
                Spacer()
                Button(tr("Lưu", "Save")) { recorder.save() }.disabled(!recorder.canSave)
            }
        }.padding(20).frame(width: 400)
    }
}
