import Foundation
import CryptoKit
import Security
import ImageIO

/// Kho clipboard cục bộ. Lock bảo vệ trạng thái và toàn bộ thao tác tệp;
/// manager dùng thêm hàng đợi nối tiếp để giữ thứ tự các snapshot.
/// Không ghi bản rõ, không tạo lại khóa khi đã có dữ liệu mã hóa.
final class ClipboardStore: @unchecked Sendable {
    typealias KeyProvider = (_ allowCreation: Bool) throws -> SymmetricKey

    enum StorageError: Error {
        case keychain(OSStatus)
        case missingKey, invalidKey, invalidFormat, unsafeFileName, notLoaded
    }

    static let header = Data("HyperMacClipboard\0\u{01}".utf8)
    let directory: URL
    let historyURL: URL
    let legacyURL: URL
    let imagesURL: URL
    private let key: SymmetricKey
    private var isLoaded = false
    private let lock = NSLock()
    private let fm = FileManager.default

    init(directory: URL, keyProvider: KeyProvider = { try ClipboardStore.keychainKey(allowCreation: $0) }) throws {
        self.directory = directory
        historyURL = directory.appendingPathComponent("clipboard.encrypted")
        legacyURL = directory.appendingPathComponent("clipboard.json")
        imagesURL = directory.appendingPathComponent("ClipboardImages", isDirectory: true)

        // Ảnh có thể đã được mã hóa trước khi quá trình chuyển đổi bị ngắt.
        let imageFiles = (try? fm.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil)) ?? []
        let hasEncryptedFiles = fm.fileExists(atPath: historyURL.path) || imageFiles.contains {
            guard let handle = try? FileHandle(forReadingFrom: $0) else { return false }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: Self.header.count)) == Self.header
        }
        key = try keyProvider(!hasEncryptedFiles)
        guard key.bitCount == 256 else { throw StorageError.invalidKey }
        for url in [directory, imagesURL] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    func load() throws -> [ClipItem] {
        lock.lock()
        defer { lock.unlock() }
        isLoaded = false
        let encryptedExists = fm.fileExists(atPath: historyURL.path)
        let legacyExists = fm.fileExists(atPath: legacyURL.path)
        var items: [ClipItem] = []
        if encryptedExists {
            let data = try open(Data(contentsOf: historyURL), context: "history")
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } else if legacyExists {
            items = try JSONDecoder().decode([ClipItem].self, from: Data(contentsOf: legacyURL))
        }

        // Kiểm tra tất cả đường dẫn trước khi chuyển đổi bất kỳ ảnh nào.
        for item in items where item.type == .image {
            _ = try imageURL(item.imageFileName ?? "\(item.id.uuidString).png")
        }
        for index in items.indices where items[index].type == .image {
            let name = items[index].imageFileName ?? "\(items[index].id.uuidString).png"
            let url = try imageURL(name)
            if fm.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if data.starts(with: Self.header) {
                    _ = try open(data, context: "image/" + name)
                } else {
                    // Không coi ciphertext bị hỏng là ảnh bản rõ để mã hóa lại.
                    guard !encryptedExists,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 else {
                        throw StorageError.invalidFormat
                    }
                    try write(data, to: url, context: "image/" + name)
                }
            } else if let data = items[index].imageData {
                try write(data, to: url, context: "image/" + name)
            }
            items[index].imageFileName = name
        }

        // Ghi + đọc xác minh trước khi xóa JSON cũ. Khi bị ngắt, lần mở sau tiếp tục
        // với cùng khóa; lịch sử mã hóa luôn được ưu tiên, không fallback về JSON.
        if encryptedExists || legacyExists || !items.isEmpty {
            let data = try JSONEncoder().encode(items)
            try write(data, to: historyURL, context: "history")
            guard try open(Data(contentsOf: historyURL), context: "history") == data else {
                throw StorageError.invalidFormat
            }
        }
        if legacyExists { try fm.removeItem(at: legacyURL) }

        // Chỉ dọn ảnh mồ côi sau khi đã mở và chuyển đổi thành công lịch sử.
        let validNames = Set(items.filter { $0.type == .image }.compactMap(\.imageFileName))
        for url in try fm.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil) {
            if !validNames.contains(url.lastPathComponent), ["png", "jpg", "jpeg", "tiff"].contains(url.pathExtension.lowercased()) {
                try fm.removeItem(at: url)
            }
        }
        isLoaded = true
        return items
    }

    func save(_ items: [ClipItem]) throws {
        try withLoadedStore {
            try write(JSONEncoder().encode(items), to: historyURL, context: "history")
        }
    }

    func saveImage(_ data: Data, named name: String) throws {
        try withLoadedStore { try write(data, to: imageURL(name), context: "image/" + name) }
    }

    func readImage(named name: String) throws -> Data {
        try withLoadedStore { try open(Data(contentsOf: imageURL(name)), context: "image/" + name) }
    }

    func deleteImage(named name: String) throws {
        try withLoadedStore {
            let url = try imageURL(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }

    private func withLoadedStore<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard isLoaded else { throw StorageError.notLoaded }
        do { return try operation() }
        catch {
            // Ngăn cả các thao tác đã xếp hàng tiếp tục ghi sau lỗi đầu tiên.
            isLoaded = false
            throw error
        }
    }

    private func imageURL(_ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw StorageError.unsafeFileName
        }
        let url = imagesURL.appendingPathComponent(name)
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw StorageError.unsafeFileName
        }
        return url
    }

    private func write(_ data: Data, to url: URL, context: String) throws {
        let aad = Self.header + Data(context.utf8)
        let box = try AES.GCM.seal(data, using: key, authenticating: aad)
        guard let combined = box.combined else { throw StorageError.invalidFormat }
        try (Self.header + combined).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func open(_ data: Data, context: String) throws -> Data {
        guard data.starts(with: Self.header) else { throw StorageError.invalidFormat }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
        return try AES.GCM.open(box, using: key, authenticating: Self.header + Data(context.utf8))
    }

    static func keychainKey(allowCreation: Bool, service: String = "com.opensource.hypermac.clipboard") throws -> SymmetricKey {
        // Login Keychain hỗ trợ cả chữ ký self-signed cố định của bản local.
        // Không đồng bộ iCloud; không ghi khóa vào UserDefaults hoặc tệp.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aes256-gcm-v1",
            kSecAttrSynchronizable as String: false
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { throw StorageError.invalidKey }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw StorageError.keychain(status) }
        guard allowCreation else { throw StorageError.missingKey }

        let key = SymmetricKey(size: .bits256)
        var attributes = query
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrLabel as String] = "HyperMac — Khóa mã hóa Clipboard"
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(attributes as CFDictionary, nil)
        // Một tiến trình khác có thể vừa tạo khóa. Luôn đọc khóa đã lưu, không ghi đè.
        guard added == errSecSuccess || added == errSecDuplicateItem else { throw StorageError.keychain(added) }
        return try keychainKey(allowCreation: false, service: service)
    }
}
