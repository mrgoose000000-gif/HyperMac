import Foundation

/// Runtime hardware detection, shared across managers.
///
/// Dùng `machdep.cpu.brand_string` làm nguồn phân biệt kiến trúc (KHÔNG dùng `uname -m`):
/// dưới Rosetta, một quy trình x86_64 chạy trên máy Apple Silicon vẫn báo `uname -m = x86_64`,
/// nhưng brand string vẫn là `"Apple M1/M2..."` — vậy đây là nguồn đáng tin cậy duy nhất.
public enum HardwareInfo {
    /// `"Apple M2"`, `"Apple M3 Max"`, ... → Apple Silicon.
    public static var isAppleSilicon: Bool {
        brandString.contains("Apple")
    }

    /// Mac Intel (x86_64). Đảo của `isAppleSilicon` — an toàn vì cả hai trường hợp đều xác định.
    public static var isIntel: Bool { !isAppleSilicon }

    /// `machdep.cpu.brand_string` — ví dụ `"Intel(R) Core(TM) i5-5350U CPU @ 1.80GHz"`.
    public static var brandString: String {
        sysctlString("machdep.cpu.brand_string") ?? ""
    }

    /// `hw.model` — ví dụ `"MacBookAir7,2"` (MBA Early 2015), `"Mac14,2"` (MacBook Air M2).
    public static var modelIdentifier: String {
        sysctlString("hw.model") ?? ""
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
