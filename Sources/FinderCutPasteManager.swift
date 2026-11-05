import Foundation
import AppKit
import SwiftUI

// Fast lock-free flags for eventTapCallback (Session level)
public var gIsFinderCutPasteEnabled: Bool = true
public var gIsFinderCutActive: Bool = false
public var gIsSynthesizingEvent: Bool = false

// MARK: - Toast View for Finder Cut & Paste Feedback

public struct FinderCutToastView: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let subtitle: String?

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: FS.title, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: FS.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: FS.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 220, maxWidth: 360, minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: Rad.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Rad.lg, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
        )
    }
}

// MARK: - Finder Cut & Paste Manager Singleton

@MainActor
public class FinderCutPasteManager: ObservableObject {
    public static let shared = FinderCutPasteManager()

    @Published public var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "finder_cut_paste_enabled")
            gIsFinderCutPasteEnabled = isEnabled
            if !isEnabled {
                cancelCut(quiet: true)
            }
        }
    }

    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "finder_cut_details_expanded")
        }
    }

    @Published public var isCutActive: Bool = false
    @Published public var cutFileNames: [String] = []

    private var cutURLs: [URL] = []
    private var cutChangeCount: Int = -1
    private var toastPanel: NSPanel?
    private var toastDismissWorkItem: DispatchWorkItem?

    private init() {
        if UserDefaults.standard.object(forKey: "finder_cut_paste_enabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "finder_cut_paste_enabled")
        } else {
            self.isEnabled = true
        }
        gIsFinderCutPasteEnabled = self.isEnabled

        if UserDefaults.standard.object(forKey: "finder_cut_details_expanded") != nil {
            self.isDetailsExpanded = UserDefaults.standard.bool(forKey: "finder_cut_details_expanded")
        }

        setupToastPanel()
    }

    // MARK: - Setup Floating Toast Panel

    private func setupToastPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.toastPanel = panel
    }

    // MARK: - Frontmost & Text Editing Inspection

    nonisolated public static func isFinderFrontmost() -> Bool {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Determines if Finder's focused element is a text field (e.g. renaming a file or searching).
    nonisolated public static func isFinderEditingText() -> Bool {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else {
            return false
        }

        let appElement = AXUIElementCreateApplication(finder.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement as! AXUIElement? else {
            return false
        }

        var role: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String {
            if roleStr == "AXTextField" || roleStr == "AXTextArea" || roleStr == "AXComboBox" {
                return true
            }
        }

        var subrole: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subroleStr = subrole as? String {
            if subroleStr == "AXSearchField" {
                return true
            }
        }

        return false
    }

    // MARK: - Cut Action (Triggered on ⌘X)

    public func triggerCut() {
        guard isEnabled else { return }

        // Synthesize Command + C to copy selected file(s) into pasteboard
        synthesizeCmdC()

        // Give Finder 50ms to update pasteboard with selected file URLs
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let pb = NSPasteboard.general
            let urls = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
            let fileURLs = urls.filter { $0.isFileURL }

            if !fileURLs.isEmpty {
                self.cutURLs = fileURLs
                self.cutFileNames = fileURLs.map { $0.lastPathComponent }
                self.cutChangeCount = pb.changeCount
                self.isCutActive = true
                gIsFinderCutActive = true

                NSSound(named: "Tink")?.play()

                let title: String
                if fileURLs.count == 1 {
                    title = tr("Đã cắt: \(fileURLs[0].lastPathComponent)", "Cut: \(fileURLs[0].lastPathComponent)")
                } else {
                    title = tr("Đã cắt \(fileURLs.count) tệp và thư mục", "Cut \(fileURLs.count) items")
                }

                self.showToast(
                    icon: "scissors",
                    iconColor: .secondary,
                    title: title,
                    subtitle: tr("Bấm ⌘V để di chuyển • Esc để huỷ", "Press ⌘V to move • Esc to cancel")
                )
                appLog("✂️ FinderCutPaste: Cut \(fileURLs.count) item(s)")
            } else {
                // Nothing cut
                self.isCutActive = false
                gIsFinderCutActive = false
                self.cutURLs = []
                self.cutFileNames = []
            }
        }
    }

    // MARK: - Paste Action (Triggered on ⌘V when Cut is active)

    public func triggerPaste() {
        guard isEnabled && isCutActive else { return }

        let pb = NSPasteboard.general

        // Verify if pasteboard was superseded by another copy operation
        if self.cutChangeCount != -1 && pb.changeCount != self.cutChangeCount {
            appLog("⚠️ FinderCutPaste: Pasteboard changed since cut; cancelling cut state.")
            cancelCut(quiet: true)
            return
        }

        let count = cutURLs.count
        let first = cutFileNames.first ?? "tệp"

        // Synthesize Option + Command + V (Native Finder "Move Item Here")
        synthesizeOptCmdV()

        // Clear cut state
        self.isCutActive = false
        gIsFinderCutActive = false
        self.cutURLs = []
        self.cutFileNames = []
        self.cutChangeCount = -1

        let title: String
        if count == 1 {
            title = tr("Đã di chuyển: \(first)", "Moved: \(first)")
        } else if count > 1 {
            title = tr("Đã di chuyển \(count) tệp và thư mục", "Moved \(count) items")
        } else {
            title = tr("Đã di chuyển thành công", "Successfully moved")
        }

        showToast(
            icon: "shippingbox.fill",
            iconColor: .secondary,
            title: title,
            subtitle: tr("Đã hoàn tất di chuyển vào thư mục hiện tại", "Successfully moved to current folder")
        )
        appLog("📦 FinderCutPaste: Moved \(count) item(s) via ⌥⌘V")
    }

    // MARK: - Cancel Cut (Triggered on Esc or explicit ⌘C)

    public func cancelCut(quiet: Bool = false) {
        guard isCutActive else { return }

        self.isCutActive = false
        gIsFinderCutActive = false
        self.cutURLs = []
        self.cutFileNames = []
        self.cutChangeCount = -1

        if !quiet {
            showToast(
                icon: "xmark.circle.fill",
                iconColor: .secondary,
                title: tr("Đã huỷ lệnh cắt", "Cut Cancelled"),
                subtitle: tr("Tệp vẫn giữ nguyên vị trí cũ", "Files remained in original location")
            )
            NSSound(named: "Pop")?.play()
        }
        appLog("✕ FinderCutPaste: Cut cancelled (quiet=\(quiet))")
    }

    // MARK: - Keystroke Synthesis

    private func synthesizeCmdC() {
        gIsSynthesizingEvent = true
        let src = CGEventSource(stateID: .combinedSessionState)

        if let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) { // 8 is C
            down.flags = .maskCommand
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cgSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            gIsSynthesizingEvent = false
        }
    }

    private func synthesizeOptCmdV() {
        gIsSynthesizingEvent = true
        let src = CGEventSource(stateID: .combinedSessionState)

        if let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) { // 9 is V
            down.flags = [.maskCommand, .maskAlternate]
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
            up.flags = [.maskCommand, .maskAlternate]
            up.post(tap: .cgSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            gIsSynthesizingEvent = false
        }
    }

    // MARK: - Toast Presentation & Auto-dismiss

    private func showToast(icon: String, iconColor: Color, title: String, subtitle: String?) {
        guard let panel = self.toastPanel else { return }

        toastDismissWorkItem?.cancel()

        let rootView = FinderCutToastView(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle
        )

        let hostingView = NSHostingView(rootView: rootView)
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        // Position at bottom center of the active screen (above Dock)
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        if let s = targetScreen {
            let screenRect = s.frame
            let x = screenRect.origin.x + (screenRect.width - fittingSize.width) / 2
            let y = screenRect.origin.y + 90
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let panel = panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            self?.toastDismissWorkItem = nil
        }

        self.toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}
