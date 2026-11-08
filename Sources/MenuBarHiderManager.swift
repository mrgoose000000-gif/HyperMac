import Cocoa
import SwiftUI

// MARK: - Menu Bar App Item

public struct MenuBarAppItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let icon: NSImage
    public let pid: pid_t
    public let bundleIdentifier: String
    public let runningApp: NSRunningApplication

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MenuBarAppItem, rhs: MenuBarAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Menu Bar Spacing Modes for Notch Fix

public enum MenuBarSpacingMode: Int, CaseIterable, Identifiable {
    case compact = 6       // 6px - Tối ưu nhất cho màn hình tai thỏ (Notch)
    case medium = 10      // 10px - Vừa phải
    case appleDefault = 0  // Mặc định của Apple (~18px)

    public var id: Int { self.rawValue }

    public var title: String {
        switch self {
        case .compact: return tr("Siêu gọn 6px (Tối ưu cho Tai thỏ)", "Compact 6px (Notch Optimized)")
        case .medium: return tr("Vừa phải 10px", "Medium 10px")
        case .appleDefault: return tr("Mặc định Apple (~18px)", "Apple Default (~18px)")
        }
    }
}

// MARK: - Fast lock-free flag for KeyInterceptor
public var gIsMenuBarHiderEnabled: Bool = false

// MARK: - Menu Bar Drawer & Hider Manager

@MainActor
public final class MenuBarHiderManager: NSObject, ObservableObject, NSPopoverDelegate {
    public static let shared = MenuBarHiderManager()

    // Persistence Keys
    private let keyEnabled = "HyperMac_MenuBarHider_Enabled"
    private let keySpacing = "HyperMac_MenuBar_SpacingMode"

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: keyEnabled)
            gIsMenuBarHiderEnabled = isEnabled
            if isEnabled {
                setupStatusItem()
            } else {
                removeStatusItem()
            }
        }
    }

    @Published public var spacingMode: MenuBarSpacingMode {
        didSet {
            UserDefaults.standard.set(spacingMode.rawValue, forKey: keySpacing)
            applySpacingToSystem(spacingMode)
        }
    }

    @Published public var runningApps: [MenuBarAppItem] = []
    @Published public var searchText: String = ""

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private override init() {
        let enabled = UserDefaults.standard.object(forKey: keyEnabled) as? Bool ?? true
        self.isEnabled = enabled
        gIsMenuBarHiderEnabled = enabled

        let savedSpacing = UserDefaults.standard.integer(forKey: keySpacing)
        self.spacingMode = MenuBarSpacingMode(rawValue: savedSpacing) ?? .compact

        super.init()

        if enabled {
            setupStatusItem()
        }
    }

    // MARK: - Setup & Removal of Status Item

    public func setupStatusItem() {
        removeStatusItem()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "HyperMac_MenuBar_Drawer"
        if let btn = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let img = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Ngăn kéo Menu Bar")?
                .withSymbolConfiguration(config)
            img?.isTemplate = true
            btn.image = img
            btn.toolTip = tr("Ngăn kéo Menu Bar (Bấm để xem tất cả ứng dụng)", "Menu Bar Drawer (Click to view all apps)")
            btn.target = self
            btn.action = #selector(toggleDrawerAction)
        }
        self.statusItem = item
    }

    public func removeStatusItem() {
        popover?.performClose(nil)
        popover = nil

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Popover Handling

    @objc private func toggleDrawerAction() {
        toggle()
    }

    public func toggle() {
        guard isEnabled, let button = statusItem?.button else { return }

        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            return
        }

        refreshRunningApps()

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 330, height: 420)
        pop.behavior = .transient
        pop.delegate = self
        pop.contentViewController = NSHostingController(
            rootView: MenuBarDrawerPopoverView(manager: self)
        )
        self.popover = pop
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openApp(_ item: MenuBarAppItem) {
        popover?.performClose(nil)
        item.runningApp.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - App Scanning

    public func refreshRunningApps() {
        let ignored: Set<String> = [
            "com.apple.loginwindow", "com.apple.WindowManager", "com.apple.dock",
            "com.apple.systemuiserver", "com.apple.AccessibilityUIServer",
            "com.apple.wallpaper.agent", "com.apple.notificationcenterui",
            "com.apple.dock.extra", "com.apple.ViewBridgeAuxiliary",
            "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher",
            "com.apple.Spotlight", "com.apple.chronod", "com.apple.UIKitSystemApp",
            "com.apple.TextInputUI.xpc.CursorUIViewService", "com.apple.PressAndHold",
            "com.apple.SafariPlatformSupport.Helper", "com.apple.appkit.xpc.openAndSavePanelService",
            "com.apple.screencaptureui", "com.apple.UserNotificationCenter",
            "com.apple.storeuid", "com.apple.accessibility.universalAccessAuthWarn",
            "com.apple.coreservices.uiagent", "com.apple.talagent",
            "com.apple.universalcontrol", "com.apple.dock.external.extra.arm64",
            "com.apple.security.Keychain-Circle-Notification", "com.apple.LocalAuthentication.UIAgent",
            "com.apple.WorkflowKit.ShortcutsViewService", "com.apple.CoreLocationAgent",
            "com.apple.backgroundtaskmanagement.agent", "com.apple.systemevents",
            "com.apple.FolderActionsDispatcher", "com.apple.AirPlayUIAgent", "com.apple.PowerChime",
            "com.apple.controlcenter"
        ]

        var list: [MenuBarAppItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier, !ignored.contains(bundleId) else { continue }
            if bundleId.hasPrefix("com.apple.WebKit") || bundleId.contains(".helper") || bundleId.contains("Open and Save Panel") { continue }
            let name = app.localizedName ?? bundleId
            let icon = app.icon ?? (app.bundleURL != nil ? NSWorkspace.shared.icon(forFile: app.bundleURL!.path) : NSImage())
            list.append(MenuBarAppItem(
                id: "\(bundleId)_\(app.processIdentifier)",
                name: name,
                icon: icon,
                pid: app.processIdentifier,
                bundleIdentifier: bundleId,
                runningApp: app
            ))
        }

        // Prioritize third party apps, then sort by name
        list.sort { a, b in
            let aApple = a.bundleIdentifier.hasPrefix("com.apple.")
            let bApple = b.bundleIdentifier.hasPrefix("com.apple.")
            if aApple != bApple {
                return !aApple // Third-party apps first!
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        self.runningApps = list
    }

    // MARK: - Notch Spacing Fix

    private func applySpacingToSystem(_ mode: MenuBarSpacingMode) {
        DispatchQueue.global(qos: .userInitiated).async {
            if mode == .appleDefault {
                _ = shell("defaults -currentHost delete -globalDomain NSStatusItemSpacing 2>/dev/null; defaults -currentHost delete -globalDomain NSStatusItemSelectionPadding 2>/dev/null; killall ControlCenter 2>/dev/null")
            } else {
                let val = mode.rawValue
                _ = shell("defaults -currentHost write -globalDomain NSStatusItemSpacing -int \(val); defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int \(val); killall ControlCenter 2>/dev/null")
            }
        }
    }
}

// MARK: - Menu Bar Drawer Popover View (SwiftUI)

public struct MenuBarDrawerPopoverView: View {
    @ObservedObject var manager: MenuBarHiderManager

    private var filteredApps: [MenuBarAppItem] {
        if manager.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return manager.runningApps
        }
        return manager.runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(manager.searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Ngăn kéo Menu Bar", "Menu Bar Drawer"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("\(manager.runningApps.count) ứng dụng đang chạy", "\(manager.runningApps.count) running apps"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Shortcut hint
                Text("⌘⌥B")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(tr("Tìm nhanh ứng dụng...", "Search apps..."), text: $manager.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !manager.searchText.isEmpty {
                    Button {
                        manager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // App Grid / List
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(filteredApps) { item in
                        Button {
                            manager.openApp(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)

                                Text(item.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(Color.primary)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 260)

            Divider()

            // Notch Optimizer Footer
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer.and.ipad")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)

                    Text(tr("Tối ưu khoảng cách Tai thỏ (Notch):", "Notch Spacing Fix:"))
                        .font(.system(size: 10, weight: .semibold))

                    Spacer()

                    Picker("", selection: $manager.spacingMode) {
                        ForEach(MenuBarSpacingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.mini)
                    .frame(width: 140)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color.primary.opacity(0.025))
        }
        .frame(width: 330)
    }
}
