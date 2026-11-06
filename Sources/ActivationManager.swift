import Foundation
import AppKit
import Combine

// MARK: - Community Activation Manager (Zalo Group Onboarding)

@MainActor
public final class ActivationManager: ObservableObject {
    public static let shared = ActivationManager()

    public static let zaloGroupURL = URL(string: "https://zalo.me/g/8szr9b4bsdxfumgs4rwc")!
    private static let validActivationKey = "happy"
    private static let userDefaultsKey = "hypermac_activated_v1"

    @Published public var isActivated: Bool = false
    @Published public var inputKey: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var isSuccess: Bool = false

    private init() {
        self.isActivated = checkActivationStatus()
    }

    // MARK: - Check Permanent Activation

    public func checkActivationStatus() -> Bool {
        // 1. Check UserDefaults
        if UserDefaults.standard.bool(forKey: Self.userDefaultsKey) {
            return true
        }

        // 2. Check Application Support license marker file
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let licenseFile = appSupport.appendingPathComponent("HyperMac/.license_v1")
            if FileManager.default.fileExists(atPath: licenseFile.path) {
                if let content = try? String(contentsOf: licenseFile, encoding: .utf8),
                   content.trimmingCharacters(in: .whitespacesAndNewlines) == "activated_lifetime" {
                    UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
                    return true
                }
            }
        }

        // 3. Check Home Directory persistent backup file
        let homeMarker = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hypermac_activated")
        if FileManager.default.fileExists(atPath: homeMarker.path) {
            UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
            return true
        }

        return false
    }

    // MARK: - Validate Key

    @discardableResult
    public func submitKey() -> Bool {
        let clean = inputKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean == Self.validActivationKey {
            // Success!
            self.errorMessage = nil
            self.isSuccess = true
            NSSound(named: "Glass")?.play()

            // Persist activation permanently
            UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
            saveBackupLicenseFiles()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.isActivated = true
            }
            return true
        } else {
            self.errorMessage = tr(
                "Mã kích hoạt chưa đúng. Hãy kiểm tra tin nhắn ghim trong nhóm Zalo!",
                "Invalid activation key. Please check the pinned message in the Zalo group!"
            )
            NSSound(named: "Basso")?.play()
            return false
        }
    }

    // MARK: - Reset (For Testing Only)

    public func resetActivationForTesting() {
        self.isActivated = false
        self.isSuccess = false
        self.inputKey = ""
        self.errorMessage = nil
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let licenseFile = appSupport.appendingPathComponent("HyperMac/.license_v1")
            try? FileManager.default.removeItem(at: licenseFile)
        }
        let homeMarker = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hypermac_activated")
        try? FileManager.default.removeItem(at: homeMarker)
    }

    // MARK: - Save Backup License Files

    private func saveBackupLicenseFiles() {
        // App Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("HyperMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let licenseFile = dir.appendingPathComponent(".license_v1")
            try? "activated_lifetime".write(to: licenseFile, atomically: true, encoding: .utf8)
        }

        // Home marker
        let homeMarker = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hypermac_activated")
        try? "activated_lifetime".write(to: homeMarker, atomically: true, encoding: .utf8)
    }

    // MARK: - Open Zalo Group

    public func openZaloGroup() {
        NSWorkspace.shared.open(Self.zaloGroupURL)
    }

    // MARK: - QR Code Asset Loader

    public func getZaloQRImage() -> NSImage? {
        if let path = Bundle.main.path(forResource: "zalo_group_qr", ofType: "jpg"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        let fallbackPaths = [
            "/Applications/HyperMac.app/Contents/Resources/zalo_group_qr.jpg",
            FileManager.default.currentDirectoryPath + "/Resources/zalo_group_qr.jpg",
            "/Users/khacdai24/.gemini/antigravity-ide/scratch/DisplayControl/Resources/zalo_group_qr.jpg",
            "/Users/khacdai24/.gemini/antigravity/brain/94879281-6fae-438e-aee5-006283e6be3d/.user_uploaded/media_1793958997790_99220db5.jpg"
        ]
        for p in fallbackPaths {
            if FileManager.default.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) {
                return img
            }
        }
        return nil
    }
}

