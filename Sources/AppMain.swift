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
class AppDelegate: NSObject, NSApplicationDelegate {
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
        pop.contentViewController = NSHostingController(
            rootView: MainView(displayManager: DisplayManager.shared)
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

        // Start Global Key Interceptor (F1/F2, AltTab, Snapping, Clipboard)
        KeyInterceptor.shared.start()

        // Eagerly initialize Clipboard Manager
        _ = ClipboardManager.shared

        // Eagerly initialize Disk Speed sampler (biểu đồ tốc độ chép file)
        _ = DiskSpeedManager.shared

        // Register for display reconfiguration
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        VirtualDisplayManager.shared.destroyVirtualDisplay()
    }

    /// Cửa sổ xem trước UI khi đặt `HYPERMAC_PREVIEW=1` (dùng để chụp/kiểm tra layout).
    /// `HYPERMAC_PREVIEW_TAB=0|1|2` chọn tab, mặc định 1 (Pin & Phần cứng).
    /// `HYPERMAC_PREVIEW_OUT=/path.png` render thẳng ra PNG (không cần quyền chụp màn hình).
    private func showPreviewWindow() {
        let tab = Int(ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_TAB"] ?? "") ?? 1
        DisplayManager.shared.selectedMainTab = tab

        let view = MainView(displayManager: DisplayManager.shared)
            .frame(width: 380, height: 570)

        if let out = ProcessInfo.processInfo.environment["HYPERMAC_PREVIEW_OUT"], !out.isEmpty {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
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
