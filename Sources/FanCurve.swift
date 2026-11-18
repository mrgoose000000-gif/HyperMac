import Foundation

// MARK: - Fan curve (nhiệt độ → % quạt), kiểu smcFanControl / Macs Fan Control.
//
// Hoạt động trên CẢ macOS Intel lẫn Apple Silicon: chúng ta chỉ cần một nguồn nhiệt
// (từ ThermalManager, đã xử lý sp78 trên Intel và sensor riêng trên M) + lộ trình
// fan-set hiện có (F0Mn min-clamp trên Intel; F0Tg/helper trên M). Mapper bên dưới
// hoàn toàn độc lập phần cứng.

/// Một điểm trên đường cong: khi nhiệt độ `temp` (°C) thì quạt chạy `pct` (%).
public struct FanCurvePoint: Codable, Equatable, Identifiable {
    public let id: UUID
    public var temp: Double   // °C, ngưỡng nhiệt
    public var pct: Double    // % tốc độ (0...100) mà quạt sẽ chạy tại ngưỡng đó

    public init(id: UUID = UUID(), temp: Double, pct: Double) {
        self.id = id
        self.temp = temp
        self.pct = pct
    }
}

/// Nguồn nhiệt cho fan-curve (đọc từ ThermalManager — cross-arch).
public enum FanCurveTempSource: Int, CaseIterable, Codable {
    case cpuAverage = 0
    case cpuPeak = 1
    case hotspot = 2

    var label: String {
        switch self {
        case .cpuAverage: return tr("CPU Trung bình", "CPU Average")
        case .cpuPeak:    return tr("CPU nóng nhất", "CPU Hottest")
        case .hotspot:    return tr("Hotspot", "Hotspot")
        }
    }
}

/// Nhiệt độ hiện tại → % quạt theo bảng ngưỡng (nội suy tuyến tính từng đoạn).
enum FanCurveMapper {
    /// Trả % cần áp dụng cho nhiệt độ `temp` theo các điểm `pts`.
    /// - Dưới điểm đầu → lấy % của điểm đầu.
    /// - Trên điểm cuối → lấy % của điểm cuối.
    /// - Giữa hai điểm → nội suy tuyến tính.
    static func percent(for temp: Double, _ pts: [FanCurvePoint]) -> Double {
        guard let first = pts.first else { return 50 }
        guard pts.count >= 2 else { return first.pct }
        let s = pts.sorted { $0.temp < $1.temp }
        if temp <= s[0].temp { return s[0].pct }
        if temp >= s[s.count - 1].temp { return s[s.count - 1].pct }
        for i in 0..<(s.count - 1) {
            let a = s[i], b = s[i + 1]
            if temp >= a.temp, temp < b.temp {
                if b.temp <= a.temp { return b.pct }
                let r = (temp - a.temp) / (b.temp - a.temp)
                return a.pct + r * (b.pct - a.pct)
            }
        }
        return s[s.count - 1].pct
    }

    /// Bảng mặc định (điểm khởi tạo người dùng chỉnh).
    static let defaults: [FanCurvePoint] = [
        FanCurvePoint(temp: 50, pct: 20),
        FanCurvePoint(temp: 65, pct: 45),
        FanCurvePoint(temp: 80, pct: 75),
        FanCurvePoint(temp: 92, pct: 100),
    ]
}
