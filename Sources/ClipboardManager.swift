import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Clipboard Item Model

public enum ClipType: String, Codable, CaseIterable, Sendable {
    case all = "all"
    case text = "text"
    case rtf = "rtf"
    case image = "image"
    case file = "file"
    case color = "color"
    case url = "url"

    public var title: String {
        switch self {
        case .all: return "Tất cả"
        case .text: return "Văn bản"
        case .rtf: return "Định dạng"
        case .image: return "Hình ảnh"
        case .file: return "Tệp tin"
        case .color: return "Màu sắc"
        case .url: return "Liên kết"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .rtf: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .url: return "link"
        }
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let type: ClipType
    public var title: String
    public var detail: String
    public var plainText: String?
    public var rtfData: Data?
    public var imageData: Data?
    public var fileURLs: [String]?
    public var colorHex: String?
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public let timestamp: Date
    public var isPinned: Bool

    public static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned && lhs.title == rhs.title
    }

    public var relativeTimeText: String {
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed < 60 {
            return "Vừa xong"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))p trước"
        } else if elapsed < 86400 {
            return "\(Int(elapsed / 3600))h trước"
        } else {
            let days = Int(elapsed / 86400)
            return "\(days) ngày trước"
        }
    }
}

// MARK: - Clipboard Manager (Maccy Replacement Engine)

@MainActor
public class ClipboardManager: ObservableObject {
    public static let shared = ClipboardManager()

    // Published State
    @Published public var items: [ClipItem] = []
    @Published public var isMonitoringEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isMonitoringEnabled, forKey: "clipboard_monitoring_enabled")
            gIsClipboardEnabled = isMonitoringEnabled
        }
    }
    @Published public var maxItemsCount: Int = 100 {
        didSet {
            UserDefaults.standard.set(maxItemsCount, forKey: "clipboard_max_items")
            trimItems()
        }
    }
    @Published public var ignoreConcealedTypes: Bool = true {
        didSet { UserDefaults.standard.set(ignoreConcealedTypes, forKey: "clipboard_ignore_concealed") }
    }
    @Published public var shortcutText: String = "⌘ + ⇧ + C"
    @Published public var isHUDVisible: Bool = false
    @Published public var selectedIndex: Int = 0
    @Published public var searchText: String = ""
    @Published public var selectedFilter: ClipType = .all
    @Published public var hoveredItemID: UUID? = nil

    // Internal State
    private var lastChangeCount: Int = 0
    private var suppressChangeCount: Int = 0
    private var pollTimer: Timer?
    private var previousApp: NSRunningApplication?
    private var hudPanel: NSPanel?
    private let storageURL: URL

    private init() {
        // Resolve storage path: ~/Library/Application Support/HyperMac/clipboard.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hypermacDir = appSupport.appendingPathComponent("HyperMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: hypermacDir, withIntermediateDirectories: true)
        self.storageURL = hypermacDir.appendingPathComponent("clipboard.json")

        // Load Settings
        if UserDefaults.standard.object(forKey: "clipboard_monitoring_enabled") != nil {
            self.isMonitoringEnabled = UserDefaults.standard.bool(forKey: "clipboard_monitoring_enabled")
        }
        let savedMax = UserDefaults.standard.integer(forKey: "clipboard_max_items")
        if savedMax >= 20 && savedMax <= 500 {
            self.maxItemsCount = savedMax
        }
        if UserDefaults.standard.object(forKey: "clipboard_ignore_concealed") != nil {
            self.ignoreConcealedTypes = UserDefaults.standard.bool(forKey: "clipboard_ignore_concealed")
        }

        // Load stored items
        loadItemsFromDisk()

        // Init pasteboard state
        self.lastChangeCount = NSPasteboard.general.changeCount

        // Start background polling
        startMonitoring()
        gIsClipboardEnabled = isMonitoringEnabled
    }

    // MARK: - Filtered Items for Quick Search

    public var filteredItems: [ClipItem] {
        var result = items

        // Filter by Type
        if selectedFilter != .all {
            result = result.filter { $0.type == selectedFilter }
        }

        // Filter by Search Query
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.title.lowercased().contains(query) ||
                item.detail.lowercased().contains(query) ||
                (item.plainText?.lowercased().contains(query) ?? false) ||
                (item.sourceAppName?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    // MARK: - Monitoring Engine

    public func startMonitoring() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkPasteboard() {
        guard isMonitoringEnabled else { return }

        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }

        // If suppressed by self-paste, skip
        if currentCount == suppressChangeCount {
            lastChangeCount = currentCount
            return
        }
        lastChangeCount = currentCount

        let pb = NSPasteboard.general

        // 1. Check Concealed / Password Manager flags
        if ignoreConcealedTypes {
            let concealedTypes = [
                "org.nspasteboard.ConcealedType",
                "com.agilebits.onepassword",
                "de.sorcerer.KeepassX",
                "com.lastpass.LastPass",
                "org.nspasteboard.AutoGeneratedType"
            ]
            let types = pb.types?.map { $0.rawValue } ?? []
            for ct in concealedTypes {
                if types.contains(ct) {
                    return // Do not record passwords/sensitive clips
                }
            }
        }

        // 2. Capture source application metadata
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName
        let bundleID = frontApp?.bundleIdentifier

        // 3. Inspect Pasteboard Types
        // A. File URLs
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let filePaths = urls.filter { $0.isFileURL }.map { $0.path }
            if !filePaths.isEmpty {
                let count = filePaths.count
                let firstPath = filePaths.first!
                let firstFilename = (firstPath as NSString).lastPathComponent
                let title = count == 1 ? firstFilename : "\(firstFilename) (+ \(count - 1) tệp)"
                let detail = count == 1 ? firstPath : "\(count) tệp tin"

                appendClip(ClipItem(
                    id: UUID(),
                    type: .file,
                    title: title,
                    detail: detail,
                    plainText: filePaths.joined(separator: "\n"),
                    fileURLs: filePaths,
                    sourceAppName: appName,
                    sourceBundleID: bundleID,
                    timestamp: Date(),
                    isPinned: false
                ))
                return
            }
        }

        // B. Images
        if let image = NSImage(pasteboard: pb) {
            let size = image.size
            if size.width > 2 && size.height > 2 {
                let thumbnail = image.resized(maxDimension: 200)
                let tiffData = thumbnail?.tiffRepresentation
                let bitmap = tiffData.flatMap { NSBitmapImageRep(data: $0) }
                let jpgData = bitmap?.representation(using: .jpeg, properties: [.compressionFactor: 0.65])

                let title = "Ảnh (\(Int(size.width)) × \(Int(size.height))px)"
                let detail = "Định dạng ảnh clipboard"

                appendClip(ClipItem(
                    id: UUID(),
                    type: .image,
                    title: title,
                    detail: detail,
                    imageData: jpgData,
                    sourceAppName: appName,
                    sourceBundleID: bundleID,
                    timestamp: Date(),
                    isPinned: false
                ))
                return
            }
        }

        // C. Colors
        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           string.count <= 25,
           let hexColor = parseHexColor(string) {
            appendClip(ClipItem(
                id: UUID(),
                type: .color,
                title: hexColor.uppercased(),
                detail: "Mã màu RGB/Hex",
                plainText: hexColor,
                colorHex: hexColor,
                sourceAppName: appName,
                sourceBundleID: bundleID,
                timestamp: Date(),
                isPinned: false
            ))
            return
        }

        // D. URLs
        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           (string.lowercased().hasPrefix("http://") || string.lowercased().hasPrefix("https://")),
           let url = URL(string: string), url.host != nil {
            let title = string
            let detail = url.host ?? "Liên kết web"

            appendClip(ClipItem(
                id: UUID(),
                type: .url,
                title: title,
                detail: detail,
                plainText: string,
                sourceAppName: appName,
                sourceBundleID: bundleID,
                timestamp: Date(),
                isPinned: false
            ))
            return
        }

        // E. Plain & Rich Text
        if let string = pb.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = string.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let title = lines.first ?? "Văn bản"
            let charCount = string.count
            let lineCount = lines.count
            let detail = lineCount > 1 ? "\(lineCount) dòng • \(charCount) ký tự" : "\(charCount) ký tự"

            let rtfData = pb.data(forType: .rtf)

            appendClip(ClipItem(
                id: UUID(),
                type: rtfData != nil ? .rtf : .text,
                title: title,
                detail: detail,
                plainText: string,
                rtfData: rtfData,
                sourceAppName: appName,
                sourceBundleID: bundleID,
                timestamp: Date(),
                isPinned: false
            ))
            return
        }
    }

    private func appendClip(_ item: ClipItem) {
        // If identical item exists, remove old copy and re-insert at top (or keep pinned state)
        if let index = items.firstIndex(where: {
            if let p1 = $0.plainText, let p2 = item.plainText {
                return p1 == p2
            }
            if $0.type == .image && item.type == .image {
                return $0.imageData == item.imageData
            }
            if let f1 = $0.fileURLs, let f2 = item.fileURLs {
                return f1 == f2
            }
            return false
        }) {
            let existing = items.remove(at: index)
            var updated = item
            updated.isPinned = existing.isPinned // Preserve pin state
            insertSorted(updated)
        } else {
            insertSorted(item)
        }

        trimItems()
        saveItemsToDisk()
    }

    private func insertSorted(_ item: ClipItem) {
        if item.isPinned {
            // Insert after existing pinned items
            let pinnedCount = items.filter { $0.isPinned }.count
            items.insert(item, at: min(pinnedCount, items.count))
        } else {
            // Insert at the first non-pinned slot
            let pinnedCount = items.filter { $0.isPinned }.count
            items.insert(item, at: min(pinnedCount, items.count))
        }
    }

    private func trimItems() {
        let pinned = items.filter { $0.isPinned }
        let nonPinned = items.filter { !$0.isPinned }
        let allowedNonPinned = max(0, maxItemsCount - pinned.count)
        let trimmedNonPinned = Array(nonPinned.prefix(allowedNonPinned))
        self.items = pinned + trimmedNonPinned
    }

    // MARK: - Clip Actions

    public func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        let updated = items.remove(at: index)
        insertSorted(updated)
        saveItemsToDisk()
    }

    public func deleteItem(_ item: ClipItem) {
        items.removeAll(where: { $0.id == item.id })
        saveItemsToDisk()
        if selectedIndex >= filteredItems.count {
            selectedIndex = max(0, filteredItems.count - 1)
        }
    }

    public func clearAllHistory() {
        // Keep pinned items, delete others
        items = items.filter { $0.isPinned }
        saveItemsToDisk()
        selectedIndex = 0
    }

    // MARK: - Direct Paste Action

    public func pasteItem(_ item: ClipItem) {
        // 1. Write item into Pasteboard
        let pb = NSPasteboard.general
        pb.clearContents()

        if let rtf = item.rtfData {
            pb.setData(rtf, forType: .rtf)
        }
        if let text = item.plainText {
            pb.setString(text, forType: .string)
        }
        if let imgData = item.imageData, let img = NSImage(data: imgData) {
            pb.writeObjects([img])
        }
        if let paths = item.fileURLs {
            let urls = paths.map { NSURL(fileURLWithPath: $0) }
            pb.writeObjects(urls)
        }

        // Suppress next change count so our own paste doesn't create duplicate
        self.suppressChangeCount = pb.changeCount
        self.lastChangeCount = pb.changeCount

        // 2. Hide HUD panel
        hideHUD()

        // 3. Re-activate target previous application
        let appToActivate = previousApp ?? NSWorkspace.shared.runningApplications.first(where: { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier })

        if let app = appToActivate {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // 4. Synthesize Command + V keystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let src = CGEventSource(stateID: .combinedSessionState)
            // Virtual key 9 = 'V'
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) {
                down.flags = .maskCommand
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
                up.flags = .maskCommand
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Floating HUD Window Management

    public func toggleHUD() {
        if isHUDVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    public func showHUD() {
        guard !isHUDVisible else { return }

        // Remember target app to paste back into
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousApp = front
        }

        // Reset search & selection
        self.searchText = ""
        self.selectedFilter = .all
        self.selectedIndex = 0
        self.isHUDVisible = true
        gIsClipboardHUDVisible = true

        if hudPanel == nil {
            createHUDPanel()
        }

        // Position HUD near mouse or center of active screen
        if let panel = hudPanel {
            let mouseLoc = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]

            let panelWidth: CGFloat = 430
            let panelHeight: CGFloat = 520

            // Center horizontally on screen, slightly above center vertically
            let x = screen.visibleFrame.midX - (panelWidth / 2)
            let y = screen.visibleFrame.midY - (panelHeight / 2) + 40

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    public func hideHUD() {
        guard isHUDVisible else { return }
        self.isHUDVisible = false
        gIsClipboardHUDVisible = false
        hudPanel?.orderOut(nil)
    }

    private func createHUDPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        let hosting = NSHostingView(rootView: ClipboardOverlayView(manager: self))
        panel.contentView = hosting
        self.hudPanel = panel
    }

    // MARK: - Disk Persistence

    private func saveItemsToDisk() {
        let itemsToSave = self.items
        let url = self.storageURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(itemsToSave)
                try data.write(to: url, options: .atomic)
            } catch {
                appLog("Failed to save clipboard items: \(error.localizedDescription)")
            }
        }
    }

    private func loadItemsFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            var loaded = try JSONDecoder().decode([ClipItem].self, from: data)

            // Compress existing large image clips to save disk & RAM footprint
            var modified = false
            for i in 0..<loaded.count {
                if loaded[i].type == .image, let imgData = loaded[i].imageData, imgData.count > 40_000 {
                    if let nsImg = NSImage(data: imgData),
                       let down = nsImg.resized(maxDimension: 200),
                       let tiff = down.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let compressed = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) {
                        loaded[i].imageData = compressed
                        modified = true
                    }
                }
            }
            self.items = loaded
            if modified {
                saveItemsToDisk()
            }
        } catch {
            appLog("Failed to load clipboard items: \(error.localizedDescription)")
        }
    }

    // Helper: Parse Hex Color
    private func parseHexColor(_ str: String) -> String? {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            let hex = String(cleaned.dropFirst())
            if hex.count == 3 || hex.count == 6 || hex.count == 8 {
                let scanner = Scanner(string: hex)
                var hexNumber: UInt64 = 0
                if scanner.scanHexInt64(&hexNumber) {
                    return cleaned
                }
            }
        }
        return nil
    }
}

// MARK: - NSImage Helpers

private extension NSImage {
    func resized(maxDimension: CGFloat) -> NSImage? {
        let w = size.width
        let h = size.height
        guard w > 0 && h > 0 else { return nil }

        let ratio = min(maxDimension / w, maxDimension / h)
        if ratio >= 1.0 { return self }

        let newSize = NSSize(width: floor(w * ratio), height: floor(h * ratio))
        let target = NSImage(size: newSize)
        target.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
        target.unlockFocus()
        return target
    }
}
