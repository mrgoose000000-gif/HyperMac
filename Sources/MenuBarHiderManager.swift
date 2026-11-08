import Cocoa
import SwiftUI
@preconcurrency import ApplicationServices

public var gIsMenuBarHiderEnabled = false

struct MenuBarDrawerItem: Identifiable {
    let id: String
    let name: String
    let appName: String
    let icon: NSImage
    let element: AXUIElement?
    var additionalElements: [AXUIElement] = []
}

// Hallmark · native drawer · Theme tokens · pre-emit critique: P4 H4 E4 S5 R4 V4
@MainActor
public final class MenuBarHiderManager: NSObject, ObservableObject, NSPopoverDelegate {
    public static let shared = MenuBarHiderManager()
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "HyperMac_MenuBarHider_Enabled")
            gIsMenuBarHiderEnabled = isEnabled
            if isEnabled { setupStatusItem() } else { removeStatusItem() }
        }
    }
    @Published public private(set) var isExpanded = false
    @Published private(set) var items: [MenuBarDrawerItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var needsAccessibility = false
    @Published private(set) var message: String?
    @Published var searchText = ""
    @Published private(set) var preferences = MenuBarDrawerPreferences.load(from: .standard)
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var scanGeneration = 0
    private let worker = DispatchQueue(label: "com.hypermac.menubar.accessibility", qos: .userInitiated)

    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: "HyperMac_MenuBarHider_Enabled") as? Bool ?? true
        super.init()
        gIsMenuBarHiderEnabled = isEnabled
        if isEnabled { setupStatusItem() }
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled, self.popover?.isShown == true else { return }
            self.refresh()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    var orderedItems: [MenuBarDrawerItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return preferences.sortedIDs(items.map(\.id)).compactMap { byID[$0] }
    }

    public func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "HyperMac_MenuBar_Drawer"
        item.button?.image = NSImage(systemSymbolName: "tray", accessibilityDescription: tr("Mở ngăn kéo Menu Bar", "Open Menu Bar drawer"))
        item.button?.image?.isTemplate = true
        item.button?.toolTip = tr("Ngăn kéo Menu Bar · ⌘⌥B", "Menu Bar drawer · ⌘⌥B")
        item.button?.target = self
        item.button?.action = #selector(toggleAction)
        statusItem = item
        // Read external menu items only when the drawer is opened.
    }

    public func removeStatusItem() {
        refreshWork?.cancel()
        popover?.performClose(nil)
        popover = nil
        scanGeneration += 1
        isLoading = false
        isExpanded = false
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    @objc private func toggleAction() { toggle() }

    public func toggle(refreshItems: Bool = true) {
        guard isEnabled, let button = statusItem?.button else { return }
        if let popover, popover.isShown { popover.performClose(nil); return }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.delegate = self
        pop.contentSize = NSSize(width: 360, height: 420)
        pop.contentViewController = NSHostingController(rootView: MenuBarDrawerView(manager: self))
        popover = pop
        isExpanded = true
        if refreshItems { searchText = "" }
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if refreshItems { refresh() }
    }

    public func popoverDidClose(_ notification: Notification) { isExpanded = false }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func ownItem() -> MenuBarDrawerItem {
        MenuBarDrawerItem(id: "hypermac", name: "HyperMac", appName: "HyperMac",
                          icon: NSApp.applicationIconImage, element: nil)
    }

    func refresh() {
        guard !isLoading else { return }
        message = nil
        needsAccessibility = !AXIsProcessTrusted()
        guard !needsAccessibility else { items = [ownItem()]; return }
        isLoading = true
        scanGeneration += 1
        let generation = scanGeneration
        let systemHosts: Set<String> = [
            "com.apple.controlcenter", "com.apple.systemuiserver",
            "com.apple.Spotlight", "com.apple.notificationcenterui",
            "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher",
            "com.apple.dock", "com.apple.WindowManager",
            "com.apple.AccessibilityUIServer", "com.apple.screencaptureui"
        ]
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, String, NSImage)? in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = app.bundleIdentifier,
                  !systemHosts.contains(bundleID),
                  app.activationPolicy != .prohibited,
                  let name = app.localizedName else { return nil }
            return (app.processIdentifier, bundleID, name, app.icon ?? NSImage())
        }
        let hypermac = ownItem()
        worker.async { [weak self] in
            var result: [MenuBarDrawerItem] = [hypermac]
            var seenBundles: Set<String> = []
            for (pid, bundleID, name, icon) in apps {
                guard !seenBundles.contains(bundleID) else { continue }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                var rawBar: CFTypeRef?
                guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &rawBar) == .success,
                      let rawBar, CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { continue }
                let bar = unsafeBitCast(rawBar, to: AXUIElement.self)
                var rawChildren: CFTypeRef?
                guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &rawChildren) == .success,
                      let children = rawChildren as? [AXUIElement] else { continue }
                // One row per app, backed by its first actionable status item.
                // Menu labels such as Now Playing are not application names.
                let actionable = children.filter { element in
                    var rawActions: CFArray?
                    guard AXUIElementCopyActionNames(element, &rawActions) == .success,
                          let actions = rawActions as? [String] else { return false }
                    return actions.contains(kAXPressAction) || actions.contains(kAXShowMenuAction)
                }
                guard let element = actionable.first else { continue }
                seenBundles.insert(bundleID)
                result.append(MenuBarDrawerItem(id: bundleID, name: name, appName: name, icon: icon, element: element, additionalElements: Array(actionable.dropFirst())))
            }
            let scannedItems = result.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                self.synchronizeOrder(with: scannedItems)
                self.items = scannedItems
                self.isLoading = false
            }
        }
    }

    private func synchronizeOrder(with currentItems: [MenuBarDrawerItem]) {
        let positions = currentItems.compactMap { item -> (String, CGFloat)? in
            if let element = item.element {
                var position: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                      let position, CFGetTypeID(position) == AXValueGetTypeID() else { return nil }
                var point = CGPoint.zero
                guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point), point.x.isFinite else { return nil }
                return (item.id, point.x)
            }
            guard let button = (NSApp.delegate as? AppDelegate)?.mainMenuBarButton,
                  let window = button.window else { return nil }
            return (item.id, window.convertToScreen(button.convert(button.bounds, to: nil)).minX)
        }
        let liveIDs = positions.sorted { $0.1 < $1.1 }.map { $0.0 }
        let unknown = currentItems.map(\.id).filter { !liveIDs.contains($0) }
        // An unreadable item must not prevent all the other icons from syncing.
        preferences.order = liveIDs + unknown + preferences.order.filter {
            !liveIDs.contains($0) && !unknown.contains($0)
        }
        preferences.save(to: .standard)
        appLog("MenuBar: thứ tự thực tế: \(liveIDs.joined(separator: ", ")); chưa đọc được: \(unknown)")
    }

    func open(_ item: MenuBarDrawerItem) {
        popover?.performClose(nil)
        guard let element = item.element else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                (NSApp.delegate as? AppDelegate)?.togglePopover()
            }
            return
        }
        worker.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.5)
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            let names = actions as? [String] ?? []
            let action = names.contains(kAXPressAction) ? kAXPressAction : kAXShowMenuAction
            let result = AXUIElementPerformAction(element, action as CFString)
            // A menu can enter a modal tracking loop and time out despite opening.
            guard result != .success && result != .cannotComplete else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled else { return }
                if self.popover?.isShown != true { self.toggle() }
                self.message = tr("Không mở được mục “\(item.name)”. Ứng dụng có thể đã thoát hoặc không hỗ trợ thao tác Accessibility.", "Could not open “\(item.name)”. The app may have quit or may not support Accessibility actions.")
            }
        }
    }
}

// Hallmark · compact native list · pre-emit critique: P4 H4 E4 S5 R5 V4
private struct MenuBarDrawerView: View {
    @ObservedObject var manager: MenuBarHiderManager

    private var filteredItems: [MenuBarDrawerItem] {
        let query = manager.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.orderedItems.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Ngăn kéo Menu Bar", "Menu Bar drawer"))
                    .font(.system(size: FS.title, weight: .semibold))
                Spacer()
                Text("⌥⌘B").font(.system(size: FS.caption, design: .monospaced)).foregroundStyle(.secondary)
                Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(manager.isLoading)
                    .help(tr("Quét lại ứng dụng", "Refresh apps"))
            }
            TextField(tr("Tìm ứng dụng…", "Find an app…"), text: $manager.searchText)
                .textFieldStyle(.roundedBorder)
            Divider()
            if manager.needsAccessibility {
                Text(tr("Cần quyền Trợ năng để đọc và mở menu ứng dụng.", "Accessibility permission is required to read and open app menus."))
                Button(tr("Mở cài đặt Trợ năng", "Open Accessibility settings")) { manager.openAccessibilitySettings() }
                Button(tr("Kiểm tra lại", "Check again")) { manager.refresh() }
                if let hypermac = manager.items.first { Button("HyperMac") { manager.open(hypermac) } }
                Spacer()
            } else if manager.isLoading {
                ProgressView(tr("Đang đọc Menu Bar…", "Reading menu bar…"))
                Spacer()
            } else if filteredItems.isEmpty {
                Text(tr("Không có ứng dụng phù hợp.", "No matching apps.")).foregroundStyle(.secondary)
                Spacer()
            } else {
                MenuBarAppTable(manager: manager, items: filteredItems)
            }
            if let message = manager.message {
                Text(message).font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text(tr("Bấm ứng dụng để mở menu trên Menu Bar.", "Click an app to open its menu on the menu bar."))
                .font(.system(size: FS.caption)).foregroundStyle(.secondary)
        }
        .font(.system(size: FS.body))
        .padding(14)
        .frame(width: 360, height: 420)
    }
}
