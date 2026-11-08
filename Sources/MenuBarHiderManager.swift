import Cocoa
import SwiftUI

// MARK: - Fast lock-free flag for KeyInterceptor
public var gIsMenuBarHiderEnabled: Bool = false

@MainActor
public final class MenuBarHiderManager: ObservableObject {
    public static let shared = MenuBarHiderManager()

    // Persistence Keys
    private let keyEnabled = "HyperMac_MenuBarHider_Enabled"
    private let keyCollapsed = "HyperMac_MenuBarHider_Collapsed"
    private let keyAutoCollapse = "HyperMac_MenuBarHider_AutoCollapseSec"

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: keyEnabled)
            gIsMenuBarHiderEnabled = isEnabled
            if isEnabled {
                setupStatusItems()
            } else {
                removeStatusItems()
            }
        }
    }

    @Published public var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: keyCollapsed)
            applyState()
        }
    }

    /// Auto collapse timeout in seconds (0 = disabled, 5, 10, 15)
    @Published public var autoCollapseDuration: Int {
        didSet {
            UserDefaults.standard.set(autoCollapseDuration, forKey: keyAutoCollapse)
        }
    }

    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var autoCollapseTimer: Timer?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: keyEnabled)
        self.isEnabled = enabled
        gIsMenuBarHiderEnabled = enabled

        self.isCollapsed = UserDefaults.standard.object(forKey: keyCollapsed) as? Bool ?? false
        let savedDuration = UserDefaults.standard.integer(forKey: keyAutoCollapse)
        self.autoCollapseDuration = savedDuration > 0 ? savedDuration : 5 // default 5 seconds

        if enabled {
            setupStatusItems()
        }
    }

    // MARK: - Setup & Removal

    public func setupStatusItems() {
        removeStatusItems()

        // 1. Create the toggle button item (the chevron < / >)
        let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = "HyperMac_MenuBar_Toggle"
        if let btn = toggle.button {
            btn.target = self
            btn.action = #selector(toggleAction)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.toggleItem = toggle

        // 2. Create the separator item (the divider |)
        // Created immediately after toggle, so it sits to the left of toggle by default
        let separator = NSStatusBar.system.statusItem(withLength: isCollapsed ? 10000.0 : 12.0)
        separator.autosaveName = "HyperMac_MenuBar_Separator"
        if let btn = separator.button {
            btn.target = self
            btn.action = #selector(toggleAction)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.separatorItem = separator

        applyState()
    }

    public func removeStatusItems() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        if let toggle = toggleItem {
            NSStatusBar.system.removeStatusItem(toggle)
            toggleItem = nil
        }
        if let separator = separatorItem {
            NSStatusBar.system.removeStatusItem(separator)
            separatorItem = nil
        }
    }

    // MARK: - Toggle & Actions

    @objc private func toggleAction() {
        toggle()
    }

    public func toggle() {
        guard isEnabled else { return }
        isCollapsed.toggle()
    }

    public func expand() {
        guard isEnabled && isCollapsed else { return }
        isCollapsed = false
    }

    public func collapse() {
        guard isEnabled && !isCollapsed else { return }
        isCollapsed = true
    }

    // MARK: - Apply State (Visuals & Layout)

    private func applyState() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

        if isCollapsed {
            // COLLAPSED:
            // 1. Expand separator to huge width -> pushes icons to the left off-screen
            separatorItem?.length = 10000.0
            separatorItem?.button?.image = nil
            separatorItem?.button?.toolTip = ""

            // 2. Toggle button shows left chevron (<) to hint "Click to expand items on the left"
            if let btn = toggleItem?.button {
                let img = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Mở rộng Menu Bar")?
                    .withSymbolConfiguration(config)
                img?.isTemplate = true
                btn.image = img
                btn.toolTip = tr("Mở rộng Menu Bar (⌘⌥B)", "Expand Menu Bar (⌘⌥B)")
            }
        } else {
            // EXPANDED:
            // 1. Shrink separator to slim width -> icons slide back into view
            separatorItem?.length = 12.0
            if let sepBtn = separatorItem?.button {
                sepBtn.image = Self.makeDividerImage()
                sepBtn.toolTip = tr("Vách ngăn Menu Bar (Giữ ⌘ để kéo icon muốn ẩn sang bên trái)", "Menu Bar Divider (Hold ⌘ and drag icons to hide to the left)")
            }

            // 2. Toggle button shows right chevron (>) to hint "Click to collapse"
            if let btn = toggleItem?.button {
                let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Thu gọn Menu Bar")?
                    .withSymbolConfiguration(config)
                img?.isTemplate = true
                btn.image = img
                btn.toolTip = tr("Thu gọn Menu Bar (⌘⌥B)", "Collapse Menu Bar (⌘⌥B)")
            }

            // 3. Start auto-collapse countdown if configured
            if autoCollapseDuration > 0 {
                autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: Double(autoCollapseDuration), repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.collapse()
                    }
                }
            }
        }
    }

    // MARK: - Divider Image Generator

    private static func makeDividerImage() -> NSImage {
        let size = NSSize(width: 8, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: NSRect(x: 3, y: 1.5, width: 2, height: 13), xRadius: 1, yRadius: 1)
            NSColor.labelColor.withAlphaComponent(0.40).setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

