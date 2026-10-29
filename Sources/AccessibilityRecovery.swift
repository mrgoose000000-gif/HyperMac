import Foundation
import ApplicationServices

/// Tự khôi phục quyền Accessibility sau khi app được cập nhật.
///
/// Vì sao cần: bản phát hành ký ad-hoc có Designated Requirement chỉ là `cdhash`,
/// nên mỗi lần update macOS coi là app khác và vô hiệu hoá quyền đã cấp. Entry cũ
/// vẫn nằm trong System Settings (trông như đang bật) nhưng không có tác dụng;
/// người dùng thường phải xoá app khỏi danh sách rồi thêm lại mới được.
///
/// Cách xử lý: khi chưa có quyền, reset entry TCC cũ (nếu có) **một lần cho mỗi
/// phiên bản** rồi gọi prompt hệ thống. Người dùng chỉ cần bật switch, không phải
/// xoá/thêm thủ công.
@MainActor
enum AccessibilityRecovery {
    private static let lastResetVersionKey = "ax_recovery_version"

    static func handleLaunch() {
        if AXIsProcessTrusted() { return }

        let defaults = UserDefaults.standard
        let version = UpdateManager.currentVersion
        guard defaults.string(forKey: lastResetVersionKey) != version else { return }

        resetAccessibilityPermission()
        defaults.set(version, forKey: lastResetVersionKey)

        // Đợi TCC xoá xong rồi mới hỏi lại, tránh prompt bị nuốt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    private static func resetAccessibilityPermission() {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            appLog("🔐 AccessibilityRecovery: reset quyền Accessibility cho \(bundleID) (mã \(process.terminationStatus))")
        } catch {
            appLog("⚠️ AccessibilityRecovery: không reset được quyền: \(error.localizedDescription)")
        }
    }
}
