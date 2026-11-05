import SwiftUI
import AppKit

private func displayReconfigCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            DisplayManager.shared.refreshDisplays()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // UI preview window (chỉ dùng khi kiểm thử giao diện, không ảnh hưởng người dùng)
        if ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW"] == "1" {
            showPreviewWindow()
            return
        }

        // Initialize Popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 570)
        pop.behavior = .transient
        pop.delegate = self
        pop.contentViewController = NSHostingController(
            rootView: MainView(displayManager: DisplayManager.shared)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        self.popover = pop

        // Initialize Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "command.circle.fill", accessibilityDescription: "HyperMac")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Macs Fan Control Menu Bar Live Metrics
        ThermalManager.shared.onMenuBarUpdate = { [weak self] text in
            guard let button = self?.statusItem.button else { return }
            if let text = text, !text.isEmpty {
                button.title = " \(text)"
                button.imagePosition = .imageLeading
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }
        ThermalManager.shared.updateMenuBarDisplay()

        // Tự khôi phục quyền Accessibility nếu vừa update làm mất quyền
        AccessibilityRecovery.handleLaunch()

        // Start Global Key Interceptor (F1/F2, AltTab, Snapping, Clipboard)
        KeyInterceptor.shared.start()

        // Eagerly initialize Managers
        _ = ClipboardManager.shared
        _ = FinderCutPasteManager.shared
        _ = SystemCleanerManager.shared
        _ = PermissionsManager.shared
        _ = FanManager.shared

        // Register for display reconfiguration
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, nil)

        // Hook kiểm thử: giả lập popover mở/đóng mà không cần bấm menu bar.
        let env = ProcessInfo.processInfo.environment
        if env["HYPERMAC_DISKSPEED_AUTOSTART"] == "1" {
            DiskSpeedManager.shared.setPopoverVisible(true)
            if let seconds = Double(env["HYPERMAC_DISKSPEED_AUTOCLOSE"] ?? ""), seconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    DiskSpeedManager.shared.setPopoverVisible(false)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        VirtualDisplayManager.shared.destroyVirtualDisplay()
        FanManager.shared.restoreSystemSync()
    }

    /// Cửa sổ xem trước UI khi đặt `HYPERMAC_PREVIEW=1` (dùng để chụp/kiểm tra layout).
    /// `HYPERMAC_PREVIEW_TAB=0|1|2` chọn tab, mặc định 1 (Pin & Phần cứng).
    /// `HYPERMAC_PREVIEW_OUT=/path.png` render thẳng ra PNG (không cần quyền chụp màn hình).
    private func showPreviewWindow() {
        let tab = Int(ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_TAB"] ?? "") ?? 1
        DisplayManager.shared.selectedMainTab = tab

        if let langStr = ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_LANG"] {
            LanguageManager.shared.currentLanguage = (langStr.lowercased() == "en") ? .en : .vi
        }

        if let subTabStr = ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_SUBTAB"], let subTab = Int(subTabStr) {
            SystemCleanerManager.shared.selectedSection = subTab
            if subTab == 0 {
                SystemCleanerManager.shared.scanJunk()
            } else if subTab == 1 {
                SystemCleanerManager.shared.scanInstalledApps()
                if ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_INSPECT_APP"] == "1" {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                    if let app = SystemCleanerManager.shared.installedApps.first(where: { $0.bundleID == "com.google.Chrome" }) ?? SystemCleanerManager.shared.installedApps.first {
                        SystemCleanerManager.shared.inspectAppLeftovers(for: app)
                    }
                }
            } else if subTab == 2 {
                SystemCleanerManager.shared.scanLargeFiles()
            }
        } else {
            SystemCleanerManager.shared.scanJunk()
        }

        if ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_EXPAND_PERMS"] == "1" {
            PermissionsManager.shared.isExpanded = true
        }

        if ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_DONATE"] == "1" {
            UpdateManager.shared.showDonateModal = true
        }

        let waitSec = Double(ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_WAIT"] ?? "") ?? 0.25

        let view = MainView(displayManager: DisplayManager.shared)
            .frame(width: 380, height: 570)

        if let out = ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_OUT"], !out.isEmpty {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
            window.contentView = hosting
            window.layoutIfNeeded()

            RunLoop.main.run(until: Date().addingTimeInterval(waitSec))

            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
            }
            NSApp.terminate(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 570),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "HyperMac UI Preview"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Update displays before showing
            DisplayManager.shared.refreshDisplays()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // Bật/tắt bộ đo tốc độ chép file theo vòng đời popover (chỉ chạy khi bảng mở).
    func popoverDidShow(_ notification: Notification) {
        DiskSpeedManager.shared.setPopoverVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        DiskSpeedManager.shared.setPopoverVisible(false)
    }
}

// MARK: - App Main

@main
@MainActor
enum HyperMacMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
