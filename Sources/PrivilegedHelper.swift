import Foundation

/// Vị trí cài helper khóa sạc / quạt.
///
/// `/Library/PrivilegedHelperTools` luôn thuộc root:wheel 755, user thường không ghi được.
/// (Trước đây helper nằm ở `/usr/local/bin` — thư mục có thể thuộc user nếu từng cài Homebrew
/// bản Intel, và rule sudoers mở cho mọi user.)
enum PrivilegedHelper {
    static let powerPath = "/Library/PrivilegedHelperTools/com.opensource.hypermac.power"
    static let smcPath = "/Library/PrivilegedHelperTools/com.opensource.hypermac.smc"
    static let sudoersPath = "/etc/sudoers.d/hypermac_power"

    /// v3: đường dẫn mới, sudoers chỉ cho user cài, kiểm tra tham số.
    static let requiredVersion = 3

    /// Lệnh sudo gọi helper (đường dẫn tuyệt đối, không qua `$PATH`).
    static func sudo(_ arguments: String) -> String {
        "sudo -n \(powerPath) \(arguments)"
    }
}
