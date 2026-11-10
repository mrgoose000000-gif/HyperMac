import Foundation
import IOKit

/// Đọc key SMC trực tiếp qua IOKit AppleSMC: không cần root, không sinh tiến trình con.
/// Chỉ GHI mới cần helper root; ĐỌC trạng thái khóa sạc thì app tự làm được.
final class SMCKeyReader {
    static let shared = SMCKeyReader()

    private var conn: io_connect_t = 0

    private init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        if IOServiceOpen(svc, mach_task_self_, 0, &conn) != KERN_SUCCESS { conn = 0 }
        IOObjectRelease(svc)
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// Struct SMCKeyData 80 byte: key @0, keyInfo.dataSize @28, result @40, data8 (lệnh) @42, bytes @48.
    private func call(key: String, command: UInt8, size: UInt32) -> [UInt8]? {
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        withUnsafeBytes(of: Self.fourCC(key)) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = command
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        guard kr == KERN_SUCCESS, out[40] == 0 else { return nil }
        return out
    }

    /// Giá trị thô của key, nil nếu máy không có key đó.
    func read(_ key: String) -> [UInt8]? {
        // 9 = kSMCGetKeyInfo → kích thước dữ liệu; 5 = kSMCReadKey.
        guard let info = call(key: key, command: 9, size: 0) else { return nil }
        let size = info[28..<32].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard size > 0, size <= 32, let out = call(key: key, command: 5, size: size) else { return nil }
        return Array(out[48..<48 + Int(size)])
    }
}
