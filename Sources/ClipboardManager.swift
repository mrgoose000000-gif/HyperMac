import Foundation
import AppKit
import ImageIO
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
        case .all: return tr("Tất cả", "All")
        case .text: return tr("Văn bản", "Text")
        case .rtf: return tr("Định dạng", "Rich Text")
        case .image: return tr("Hình ảnh", "Images")
        case .file: return tr("Tệp tin", "Files")
        case .color: return tr("Màu sắc", "Colors")
        case .url: return tr("Liên kết", "Links")
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
    public var imageFileName: String?
    public var fileURLs: [String]?
    public var colorHex: String?
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public let timestamp: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        type: ClipType,
        title: String,
        detail: String,
        plainText: String? = nil,
        rtfData: Data? = nil,
        imageData: Data? = nil,
        imageFileName: String? = nil,
        fileURLs: [String]? = nil,
        colorHex: String? = nil,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        timestamp: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.plainText = plainText
        self.rtfData = rtfData
        self.imageData = imageData
        self.imageFileName = imageFileName
        self.fileURLs = fileURLs
        self.colorHex = colorHex
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    public static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned && lhs.title == rhs.title
    }

    public var relativeTimeText: String {
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed < 60 {
            return tr("Vừa xong", "Just now")
        } else if elapsed < 3600 {
            let m = Int(elapsed / 60)
            return tr("\(m)p trước", "\(m)m ago")
        } else if elapsed < 86400 {
            let h = Int(elapsed / 3600)
            return tr("\(h)h trước", "\(h)h ago")
        } else {
            let days = Int(elapsed / 86400)
            return tr("\(days) ngày trước", "\(days)d ago")
        }
    }
}

// MARK: - Clipboard HUD Shortcut Selection

public enum ClipboardHUDShortcut: String, CaseIterable, Codable, Sendable {
    case cmdShiftC = "cmd_shift_c"
    case cmdShiftV = "cmd_shift_v"

    public var displayShort: String {
        switch self {
        case .cmdShiftC: return "⌘⇧C"
        case .cmdShiftV: return "⌘⇧V"
        }
    }

    public var displayTitle: String {
        switch self {
        case .cmdShiftC: return "⌘ + ⇧ + C"
        case .cmdShiftV: return "⌘ + ⇧ + V"
        }
    }

    public var keyCode: Int64 {
        switch self {
        case .cmdShiftC: return 8  // kVK_ANSI_C
        case .cmdShiftV: return 9  // kVK_ANSI_V
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
            if isMonitoringEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published public var isDetailsExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isDetailsExpanded, forKey: "clipboard_details_expanded")
        }
    }
    @Published public var maxItemsCount: Int = 100 {
        didSet {
            UserDefaults.standard.set(maxItemsCount, forKey: "clipboard_max_items")
            trimItems()
        }
    }
    /// Auto-delete non-pinned clips older than this many days. 0 = never.
    @Published public var autoCleanupDays: Int = 0 {
        didSet {
            UserDefaults.standard.set(autoCleanupDays, forKey: "clipboard_auto_cleanup_days")
            applyRetentionPolicy()
            trimItems()
        }
    }
    public var hasUnlimitedHistory: Bool { maxItemsCount <= 0 }
    @Published public var ignoreConcealedTypes: Bool = true {
        didSet { UserDefaults.standard.set(ignoreConcealedTypes, forKey: "clipboard_ignore_concealed") }
    }
    @Published public var hudShortcut: ClipboardHUDShortcut = .cmdShiftC {
        didSet {
            UserDefaults.standard.set(hudShortcut.rawValue, forKey: "clipboard_hud_shortcut")
            gClipboardShortcutKeycode = hudShortcut.keyCode
            shortcutText = hudShortcut.displayTitle
        }
    }
    @Published public var shortcutText: String = "⌘ + ⇧ + C"
    @Published public var isHUDVisible: Bool = false
    @Published public var selectedIndex: Int = 0
    @Published public var searchText: String = "" {
        didSet {
            gIsClipboardSearchEmpty = searchText.isEmpty
            clampSelection()
        }
    }
    @Published public var selectedFilter: ClipType = .all {
        didSet { clampSelection() }
    }
    @Published public var hoveredItemID: UUID? = nil

    // Internal State
    private var lastChangeCount: Int = 0
    private var suppressChangeCount: Int = 0
    private var pollTimer: Timer?
    private var quickCheckGeneration: Int = 0
    private var historyResetGeneration: Int = 0
    private let imageProcessingQueue = DispatchQueue(label: "com.opensource.hypermac.clipboard.image", qos: .utility)
    private var previousApp: NSRunningApplication?
    private var hudPanel: NSPanel?
    private let storageURL: URL
    public let imagesDirURL: URL

    private init() {
        // Resolve storage paths: ~/Library/Application Support/HyperMac/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hypermacDir = appSupport.appendingPathComponent("HyperMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: hypermacDir, withIntermediateDirectories: true)
        self.storageURL = hypermacDir.appendingPathComponent("clipboard.json")
        self.imagesDirURL = hypermacDir.appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.imagesDirURL, withIntermediateDirectories: true)

        // Load Settings
        if UserDefaults.standard.object(forKey: "clipboard_monitoring_enabled") != nil {
            self.isMonitoringEnabled = UserDefaults.standard.bool(forKey: "clipboard_monitoring_enabled")
        }
        let savedMax = UserDefaults.standard.integer(forKey: "clipboard_max_items")
        if UserDefaults.standard.object(forKey: "clipboard_max_items") != nil,
           savedMax == 0 || (savedMax >= 20 && savedMax <= 5000) {
            self.maxItemsCount = savedMax
        }
        let savedCleanup = UserDefaults.standard.integer(forKey: "clipboard_auto_cleanup_days")
        if UserDefaults.standard.object(forKey: "clipboard_auto_cleanup_days") != nil,
           [0, 7, 30, 90].contains(savedCleanup) {
            self.autoCleanupDays = savedCleanup
        }
        if UserDefaults.standard.object(forKey: "clipboard_ignore_concealed") != nil {
            self.ignoreConcealedTypes = UserDefaults.standard.bool(forKey: "clipboard_ignore_concealed")
        }
        if let savedShortcut = UserDefaults.standard.string(forKey: "clipboard_hud_shortcut"),
           let shortcut = ClipboardHUDShortcut(rawValue: savedShortcut) {
            self.hudShortcut = shortcut
        } else {
            self.hudShortcut = .cmdShiftC
        }
        gClipboardShortcutKeycode = self.hudShortcut.keyCode
        self.shortcutText = self.hudShortcut.displayTitle
        self.isDetailsExpanded = UserDefaults.standard.bool(forKey: "clipboard_details_expanded")

        // Load stored items
        loadItemsFromDisk()
        applyRetentionPolicy()
        trimItems()

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
        guard isMonitoringEnabled else {
            pollTimer = nil
            return
        }
        // Fallback thưa (1.5s + tolerance) để bắt thao tác Copy bằng chuột phải;
        // phím tắt Cmd+C / Cmd+X được scheduleQuickCheck() từ KeyInterceptor bắt tức thì sau 60–300ms.
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Kích hoạt kiểm tra pasteboard nhanh (60ms -> 150ms -> 300ms) sau phím Cmd+C / Cmd+X;
    /// tự dừng ngay khi phát hiện changeCount tăng để không bỏ lỡ dữ liệu từ app nặng (Xcode/Adobe).
    public func scheduleQuickCheck() {
        guard isMonitoringEnabled else { return }
        quickCheckGeneration &+= 1
        let gen = quickCheckGeneration
        let baseline = lastChangeCount
        for delay in [0.06, 0.15, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isMonitoringEnabled, self.quickCheckGeneration == gen else { return }
                guard self.lastChangeCount == baseline else { return }
                self.checkPasteboard()
            }
        }
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
                let clipID = UUID()
                let fileName = "\(clipID.uuidString).png"
                let fileURL = self.imagesDirURL.appendingPathComponent(fileName)
                let title = "Ảnh (\(Int(size.width)) × \(Int(size.height))px)"
                let detail = "Định dạng ảnh clipboard"
                let capturedResetGen = self.historyResetGeneration

                // Trên main chỉ lấy dữ liệu thô từ pasteboard (nhanh); đổi PNG, ghi đĩa và tạo thumbnail 800px
                // (có thể mất hàng trăm ms với ảnh chụp 5K) chuyển sang luồng nền để không làm khựng UI.
                let rawPNG = pb.data(forType: .png)
                let rawTIFF = rawPNG == nil ? (pb.data(forType: .tiff) ?? image.tiffRepresentation) : nil
                let queue = self.imageProcessingQueue

                queue.async { [weak self] in
                    var originalData = rawPNG
                    if originalData == nil, let tiff = rawTIFF, let rep = NSBitmapImageRep(data: tiff) {
                        originalData = rep.representation(using: .png, properties: [:])
                    }
                    if originalData == nil {
                        originalData = rawTIFF
                    }

                    if let origData = originalData {
                        try? origData.write(to: fileURL, options: .atomic)
                    }

                    // Thumbnail tối đa 800 px (400 pt Retina) qua ImageIO (an toàn ngoài main thread).
                    let thumbData = originalData.flatMap { ClipboardManager.thumbnailPNG(from: $0, maxPixelSize: 800) }

                    Task { @MainActor [weak self] in
                        guard let self else {
                            queue.async { try? FileManager.default.removeItem(at: fileURL) }
                            return
                        }
                        guard self.isMonitoringEnabled, self.historyResetGeneration == capturedResetGen else {
                            queue.async { try? FileManager.default.removeItem(at: fileURL) }
                            return
                        }
                        self.appendClip(ClipItem(
                            id: clipID,
                            type: .image,
                            title: title,
                            detail: detail,
                            imageData: thumbData,
                            imageFileName: fileName,
                            sourceAppName: appName,
                            sourceBundleID: bundleID,
                            timestamp: Date(),
                            isPinned: false
                        ))
                    }
                }
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
        // Age-based cleanup first so a brand-new clip is never immediately dropped.
        applyRetentionPolicy()

        // If identical item exists, remove old copy and re-insert at top (or keep pinned state)
        if let index = items.firstIndex(where: {
            if let p1 = $0.plainText, let p2 = item.plainText {
                return p1 == p2
            }
            if $0.type == .image && item.type == .image {
                if let f1 = $0.imageFileName, let f2 = item.imageFileName, f1 == f2 { return true }
                if let d1 = $0.imageData, let d2 = item.imageData, d1 == d2 { return true }
                return false
            }
            if let f1 = $0.fileURLs, let f2 = item.fileURLs {
                return f1 == f2
            }
            return false
        }) {
            let existing = items.remove(at: index)
            if let oldFile = existing.imageFileName, oldFile != item.imageFileName {
                deleteFileNamed(oldFile)
            }
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
        // maxItemsCount <= 0 means "unlimited"; retention then becomes the only guard.
        let allowedNonPinned = maxItemsCount <= 0
            ? nonPinned.count
            : max(0, maxItemsCount - pinned.count)
        if allowedNonPinned < nonPinned.count {
            let excess = nonPinned.dropFirst(allowedNonPinned)
            for item in excess {
                deleteAssociatedImage(for: item)
            }
        }
        let trimmedNonPinned = Array(nonPinned.prefix(allowedNonPinned))
        self.items = pinned + trimmedNonPinned
        clampSelection()
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
        deleteAssociatedImage(for: item)
        items.removeAll(where: { $0.id == item.id })
        saveItemsToDisk()
        if selectedIndex >= filteredItems.count {
            selectedIndex = max(0, filteredItems.count - 1)
        }
    }

    public func clearAllHistory() {
        // Keep pinned items, delete others
        let unpinned = items.filter { !$0.isPinned }
        for item in unpinned {
            deleteAssociatedImage(for: item)
        }
        items = items.filter { $0.isPinned }
        saveItemsToDisk()
        selectedIndex = 0
    }

    // MARK: - Reorder Pinned Items

    public enum MoveDirection {
        case up
        case down
    }

    public func canMoveUp(id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].isPinned else { return false }
        return idx > 0 && items[idx - 1].isPinned
    }

    public func canMoveDown(id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].isPinned else { return false }
        return idx < items.count - 1 && items[idx + 1].isPinned
    }

    public func movePinnedItem(id: UUID, direction: MoveDirection) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].isPinned else { return }

        switch direction {
        case .up:
            if idx > 0 && items[idx - 1].isPinned {
                items.swapAt(idx, idx - 1)
                saveItemsToDisk()
                if let newFilteredIdx = filteredItems.firstIndex(where: { $0.id == id }) {
                    selectedIndex = newFilteredIdx
                }
            }
        case .down:
            if idx < items.count - 1 && items[idx + 1].isPinned {
                items.swapAt(idx, idx + 1)
                saveItemsToDisk()
                if let newFilteredIdx = filteredItems.firstIndex(where: { $0.id == id }) {
                    selectedIndex = newFilteredIdx
                }
            }
        }
    }

    public func moveSelectedPinned(direction: MoveDirection) {
        guard let item = selectedItem, item.isPinned else { return }
        movePinnedItem(id: item.id, direction: direction)
    }

    // MARK: - Selection & Keyboard Navigation

    public var selectedItem: ClipItem? {
        let list = filteredItems
        guard !list.isEmpty else { return nil }
        let index = min(max(0, selectedIndex), list.count - 1)
        return list[index]
    }

    public func clampSelection() {
        let count = filteredItems.count
        selectedIndex = count == 0 ? 0 : min(max(0, selectedIndex), count - 1)
    }

    public func selectNext() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    public func selectPrevious() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    public func pasteSelectedItem() {
        guard let item = selectedItem else { return }
        pasteItem(item)
    }

    public func pasteItemAt(index: Int) {
        let list = filteredItems
        guard index >= 0 && index < list.count else { return }
        pasteItem(list[index])
    }

    public func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
        clampSelection()
    }

    public func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        deleteItem(item)
        clampSelection()
    }

    // MARK: - Storage Retention & Cleanup

    /// Thông báo ngắn hiển thị sau khi người dùng bấm "Dọn ngay"/"Xoá tất cả".
    @Published public var cleanupMessage: String? = nil
    private var cleanupMessageToken: Int = 0
    /// Bấm "Xoá tất cả" lần 1 = chờ xác nhận, lần 2 (trong 4s) = xoá thật.
    @Published public var pendingClearAllConfirm: Bool = false
    private var pendingClearAllToken: Int = 0

    private func showCleanupMessage(_ text: String) {
        cleanupMessageToken &+= 1
        let token = cleanupMessageToken
        cleanupMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, self.cleanupMessageToken == token else { return }
            self.cleanupMessage = nil
        }
    }

    /// User-triggered "clean now" action. Uses the configured retention window;
    /// falls back to 30 days when automatic cleanup is off.
    public func cleanupNow() {
        let days = autoCleanupDays > 0 ? autoCleanupDays : 30
        let removed = removeItems(olderThan: days)
        let pinnedCount = items.filter { $0.isPinned }.count

        if removed > 0 {
            saveItemsToDisk()
            clampSelection()
            showCleanupMessage(tr("Đã xoá \(removed) mục cũ hơn \(days) ngày.", "Cleaned \(removed) items older than \(days) days."))
        } else if items.isEmpty {
            showCleanupMessage(tr("Lịch sử đang trống, không có gì để dọn.", "Clipboard history is empty, nothing to clean."))
        } else if items.count == pinnedCount {
            showCleanupMessage(tr("Chỉ còn \(pinnedCount) mục đã ghim — luôn được giữ lại.", "Only \(pinnedCount) pinned items left — protected from cleanup."))
        } else {
            // Feedback rõ ràng: nút đã chạy, chỉ là chưa có mục nào đủ cũ.
            showCleanupMessage(tr("Không có mục nào cũ hơn \(days) ngày. Dùng \"Xoá tất cả\" để dọn ngay.", "No items older than \(days) days. Use \"Clear All\" to clean immediately."))
        }
    }

    /// Xoá toàn bộ mục chưa ghim. Cần bấm 2 lần để tránh xoá nhầm.
    public func requestClearAllUnpinned() {
        guard !pendingClearAllConfirm else {
            pendingClearAllConfirm = false
            pendingClearAllToken &+= 1
            historyResetGeneration &+= 1
            let unpinned = items.filter { !$0.isPinned }
            for item in unpinned {
                deleteAssociatedImage(for: item)
            }
            let removed = unpinned.count
            items = items.filter { $0.isPinned }
            saveItemsToDisk()
            clampSelection()
            showCleanupMessage(removed > 0 ? tr("Đã xoá \(removed) mục (giữ lại mục đã ghim).", "Cleaned \(removed) items (preserved pinned items).") : tr("Không có mục nào để xoá.", "Nothing to delete."))
            return
        }

        let unpinned = items.filter { !$0.isPinned }.count
        guard unpinned > 0 else {
            showCleanupMessage(tr("Không có mục nào để xoá (chỉ còn mục đã ghim).", "Nothing to delete (only pinned items left)."))
            return
        }

        pendingClearAllConfirm = true
        pendingClearAllToken &+= 1
        let token = pendingClearAllToken
        showCleanupMessage(tr("Bấm lần nữa để xoá \(unpinned) mục chưa ghim.", "Press again to delete \(unpinned) unpinned items."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.pendingClearAllToken == token else { return }
            self.pendingClearAllConfirm = false
        }
    }

    /// Applies the user's automatic age-based cleanup policy.
    public func applyRetentionPolicy() {
        guard autoCleanupDays > 0 else { return }
        let removed = removeItems(olderThan: autoCleanupDays)
        if removed > 0 {
            saveItemsToDisk()
            clampSelection()
        }
    }

    @discardableResult
    private func removeItems(olderThan days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let expired = items.filter { !$0.isPinned && $0.timestamp < cutoff }
        for item in expired {
            deleteAssociatedImage(for: item)
        }
        let before = items.count
        items.removeAll { !$0.isPinned && $0.timestamp < cutoff }
        return before - items.count
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
        if item.type == .image {
            var fullImage: NSImage?
            if let fileName = item.imageFileName {
                let fileURL = imagesDirURL.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let data = try? Data(contentsOf: fileURL) {
                    fullImage = NSImage(data: data)
                    pb.setData(data, forType: .png)
                }
            }
            if fullImage == nil, let imgData = item.imageData, let img = NSImage(data: imgData) {
                fullImage = img
            }
            if let img = fullImage {
                pb.writeObjects([img])
            }
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

    // MARK: - Image File Management

    public func imageURL(for item: ClipItem) -> URL? {
        guard item.type == .image else { return nil }
        if let fileName = item.imageFileName {
            let url = imagesDirURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let fallback = imagesDirURL.appendingPathComponent("\(item.id.uuidString).png")
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    public func deleteAssociatedImage(for item: ClipItem) {
        guard item.type == .image else { return }
        if let fileName = item.imageFileName {
            deleteFileNamed(fileName)
        }
        deleteFileNamed("\(item.id.uuidString).png")
    }

    private func deleteFileNamed(_ fileName: String) {
        let fileURL = imagesDirURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
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
        gIsClipboardSearchEmpty = true
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

            // Migrate legacy image items to disk storage
            var modified = false
            for i in 0..<loaded.count {
                if loaded[i].type == .image {
                    let fileName = loaded[i].imageFileName ?? "\(loaded[i].id.uuidString).png"
                    let fileURL = self.imagesDirURL.appendingPathComponent(fileName)

                    if !FileManager.default.fileExists(atPath: fileURL.path), let imgData = loaded[i].imageData {
                        try? imgData.write(to: fileURL, options: .atomic)
                    }
                    if loaded[i].imageFileName == nil {
                        loaded[i].imageFileName = fileName
                        modified = true
                    }
                }
            }
            self.items = loaded
            if modified {
                saveItemsToDisk()
            }
            cleanupOrphanImages(validItems: loaded)
        } catch {
            appLog("Failed to load clipboard items: \(error.localizedDescription)")
        }
    }

    private func cleanupOrphanImages(validItems: [ClipItem]) {
        DispatchQueue.global(qos: .utility).async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: self.imagesDirURL.path) else { return }
            var validFileNames = Set<String>()
            for item in validItems where item.type == .image {
                if let f = item.imageFileName { validFileNames.insert(f) }
                validFileNames.insert("\(item.id.uuidString).png")
            }
            for file in files {
                if !validFileNames.contains(file) && (file.hasSuffix(".png") || file.hasSuffix(".jpg") || file.hasSuffix(".tiff")) {
                    let fileURL = self.imagesDirURL.appendingPathComponent(file)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
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

// MARK: - Thumbnail

extension ClipboardManager {
    /// Thu nhỏ ảnh bằng ImageIO (an toàn ngoài main thread, không giải mã toàn bộ ảnh gốc vào RAM).
    nonisolated static func thumbnailPNG(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, nil)
        return CGImageDestinationFinalize(dest) ? output as Data : nil
    }
}
