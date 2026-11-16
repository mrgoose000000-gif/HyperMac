import Testing
import Foundation
import CryptoKit
import Security
@testable import HyperMac

struct ClipboardStoreTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5WQAAAAASUVORK5CYII=")!

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HyperMac-ClipboardTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func loginKeychainPersistsOneKeyAndDoesNotCreateWhenDisallowed() throws {
        // Item kiểm thử riêng, không đọc/ghi khóa thật hoặc lịch sử của người dùng.
        let service = "com.opensource.hypermac.clipboard.tests." + UUID().uuidString
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "aes256-gcm-v1"
            ] as CFDictionary)
        }
        #expect(throws: (any Error).self) { try ClipboardStore.keychainKey(allowCreation: false, service: service) }
        let first = try ClipboardStore.keychainKey(allowCreation: true, service: service)
        let reopened = try ClipboardStore.keychainKey(allowCreation: false, service: service)
        let reused = try ClipboardStore.keychainKey(allowCreation: true, service: service)
        #expect(first.bitCount == 256)
        #expect(first.withUnsafeBytes { Data($0) } == reopened.withUnsafeBytes { Data($0) })
        #expect(first.withUnsafeBytes { Data($0) } == reused.withUnsafeBytes { Data($0) })
    }

    @Test func encryptedHistoryAndOriginalImagesSurviveRestart() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        #expect(try store.load().isEmpty)
        let text = ClipItem(type: .rtf, title: "private-title", detail: "private-detail", plainText: "secret-password-123", rtfData: Data("{rtf-secret}".utf8), sourceAppName: "private-app", isPinned: true)
        let image = ClipItem(type: .image, title: "screenshot", detail: "", imageData: png, imageFileName: "original.png")
        try store.saveImage(png, named: "original.png")
        try store.save([text, image])
        let first = try Data(contentsOf: store.historyURL)
        let original = try Data(contentsOf: store.imagesURL.appendingPathComponent("original.png"))
        #expect(first.starts(with: ClipboardStore.header))
        #expect(first.range(of: Data("secret-password-123".utf8)) == nil)
        #expect(first.range(of: png) == nil)
        #expect(original != png)
        try store.save([text, image])
        #expect(try Data(contentsOf: store.historyURL) != first) // nonce mới mỗi lần lưu
        let reopened = try ClipboardStore(directory: directory) { allowCreation in
            #expect(!allowCreation)
            return key
        }
        let loaded = try reopened.load()
        #expect(loaded.count == 2)
        #expect(loaded.first?.isPinned == true)
        #expect(loaded.first?.plainText == text.plainText)
        #expect(loaded.first?.rtfData == text.rtfData)
        #expect(loaded.last?.imageData == png)
        #expect(try reopened.readImage(named: "original.png") == png)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: store.historyURL.path)[.posixPermissions] as? Int
        #expect(directoryMode == 0o700)
        #expect(fileMode == 0o600)
        try reopened.deleteImage(named: "original.png")
        #expect(!FileManager.default.fileExists(atPath: reopened.imagesURL.appendingPathComponent("original.png").path))
    }

    @Test func migratesLegacyHistoryImagesAndEmbeddedImagesWithoutLosingFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        let first = ClipItem(type: .image, title: "old-image", detail: "", imageData: png, imageFileName: "old.png", isPinned: true)
        let embedded = ClipItem(type: .image, title: "embedded", detail: "", imageData: png)
        let file = ClipItem(type: .file, title: "file", detail: "", fileURLs: ["/Users/test/private.txt"])
        try JSONEncoder().encode([first, embedded, file]).write(to: store.legacyURL)
        try png.write(to: store.imagesURL.appendingPathComponent("old.png"))
        try png.write(to: store.imagesURL.appendingPathComponent("orphan.png"))
        let loaded = try store.load()
        #expect(loaded.map(\.id) == [first.id, embedded.id, file.id])
        #expect(loaded.first?.isPinned == true)
        #expect(loaded.last?.fileURLs == file.fileURLs)
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.imagesURL.appendingPathComponent("orphan.png").path))
        #expect(try store.readImage(named: "old.png") == png)
        #expect(try store.readImage(named: "\(embedded.id.uuidString).png") == png)
        let reopened = try ClipboardStore(directory: directory) { _ in key }
        #expect(try reopened.load().map(\.id) == loaded.map(\.id))
    }

    @Test func interruptedMigrationRetainsLegacyIndexAndResumesWithSameKey() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        let item = ClipItem(type: .image, title: "image", detail: "", imageData: png, imageFileName: "old.png")
        // Một ảnh hợp lệ được chuyển trước khi gặp ảnh bị hỏng.
        let broken = ClipItem(type: .image, title: "broken", detail: "", imageFileName: "broken.png")
        try JSONEncoder().encode([item, broken]).write(to: store.legacyURL)
        let originalIndex = try Data(contentsOf: store.legacyURL)
        try png.write(to: store.imagesURL.appendingPathComponent("old.png"))
        try Data("not-an-image".utf8).write(to: store.imagesURL.appendingPathComponent("broken.png"))
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.legacyURL) == originalIndex)
        #expect(throws: (any Error).self) { try store.save([]) }
        let resumed = try ClipboardStore(directory: directory) { allowCreation in
            #expect(!allowCreation)
            return key
        }
        try png.write(to: resumed.imagesURL.appendingPathComponent("broken.png"))
        #expect(try resumed.load().count == 2)
        #expect(try resumed.readImage(named: "old.png") == png)
    }

    @Test func wrongKeyAndTamperingCannotOverwriteHistoryOrFallBackToLegacy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        _ = try store.load()
        try store.save([ClipItem(type: .text, title: "private", detail: "", plainText: "secret")])
        let original = try Data(contentsOf: store.historyURL)
        try Data("[]".utf8).write(to: store.legacyURL)
        let wrongKey = try ClipboardStore(directory: directory) { _ in SymmetricKey(size: .bits256) }
        #expect(throws: (any Error).self) { try wrongKey.load() }
        #expect(throws: (any Error).self) { try wrongKey.save([]) }
        #expect(try Data(contentsOf: store.historyURL) == original)
        #expect(FileManager.default.fileExists(atPath: store.legacyURL.path))
        var tampered = original
        tampered[tampered.count - 1] ^= 1
        try tampered.write(to: store.historyURL)
        let corrupted = try ClipboardStore(directory: directory) { _ in key }
        #expect(throws: (any Error).self) { try corrupted.load() }
        #expect(throws: (any Error).self) { try corrupted.save([]) }
        #expect(try Data(contentsOf: store.historyURL) == tampered)
    }

    @Test func missingOrUnavailableKeyNeverReplacesEncryptedData() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        _ = try store.load()
        try store.save([ClipItem(type: .text, title: "private", detail: "")])
        let original = try Data(contentsOf: store.historyURL)
        #expect(throws: (any Error).self) {
            _ = try ClipboardStore(directory: directory) { allowCreation in
                #expect(!allowCreation)
                throw ClipboardStore.StorageError.missingKey
            }
        }
        #expect(try Data(contentsOf: store.historyURL) == original)
    }

    @Test func imagesRejectTamperingSwappingAndPathTraversal() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        _ = try store.load()
        try store.saveImage(png, named: "a.png")
        try store.saveImage(png, named: "b.png")
        let a = store.imagesURL.appendingPathComponent("a.png")
        let b = store.imagesURL.appendingPathComponent("b.png")
        try Data(contentsOf: a).write(to: b)
        #expect(throws: (any Error).self) { try store.readImage(named: "b.png") }
        #expect(throws: (any Error).self) { try store.save([]) } // lỗi trước đó khóa cả ghi
        let fresh = try ClipboardStore(directory: directory) { _ in key }
        _ = try fresh.load()
        #expect(throws: (any Error).self) { try fresh.saveImage(png, named: "../escape.png") }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("escape.png").path))
    }

    @Test func malformedLegacyAndSymlinkImagesArePreservedOnFailure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        let invalid = Data("malformed-json".utf8)
        try invalid.write(to: store.legacyURL)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.legacyURL) == invalid)
        let outside = directory.appendingPathComponent("outside.png")
        try png.write(to: outside)
        let item = ClipItem(type: .image, title: "symlink", detail: "", imageFileName: "link.png")
        try JSONEncoder().encode([item]).write(to: store.legacyURL)
        try FileManager.default.createSymbolicLink(at: store.imagesURL.appendingPathComponent("link.png"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: outside) == png)
        #expect(FileManager.default.fileExists(atPath: store.legacyURL.path))
    }

    @Test func encryptedIndexWinsOverStalePlaintextAfterInterruptedCleanup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        _ = try store.load()
        let item = ClipItem(type: .text, title: "current", detail: "", plainText: "current-secret", isPinned: true)
        try store.save([item])
        try Data("[]".utf8).write(to: store.legacyURL)
        let reopened = try ClipboardStore(directory: directory) { _ in key }
        #expect(try reopened.load().first?.plainText == "current-secret")
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL.path))
    }

    @Test func replacingEncryptedImageWithPlaintextCannotBypassAuthentication() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = try ClipboardStore(directory: directory) { _ in key }
        _ = try store.load()
        let item = ClipItem(type: .image, title: "private-image", detail: "", imageData: png, imageFileName: "original.png")
        try store.saveImage(png, named: "original.png")
        try store.save([item])
        let originalIndex = try Data(contentsOf: store.historyURL)
        // Ảnh bản rõ hợp lệ vẫn phải bị từ chối sau khi đã chuyển đổi kho.
        let imageURL = store.imagesURL.appendingPathComponent("original.png")
        try png.write(to: imageURL)
        let reopened = try ClipboardStore(directory: directory) { _ in key }
        #expect(throws: (any Error).self) { try reopened.load() }
        #expect(throws: (any Error).self) { try reopened.save([]) }
        #expect(try Data(contentsOf: store.historyURL) == originalIndex)
        #expect(try Data(contentsOf: imageURL) == png)
    }
}
