import Foundation
import IOKit
import AppKit

// MARK: - Direct AppleSMC Fan Telemetry Reader (Zero Process Spawn, 0% CPU)

private final class SMCFanReader {
    private var conn: io_connect_t = 0

    init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        if IOServiceOpen(svc, mach_task_self_, 0, &conn) != KERN_SUCCESS { conn = 0 }
        IOObjectRelease(svc)
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        b[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private func readBytes(key: String, size: UInt32) -> [UInt8]? {
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        let code = Self.fourCC(key)
        withUnsafeBytes(of: code) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = 5 // kSMCReadKey
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        guard kr == KERN_SUCCESS && out[40] == 0 else { return nil }
        return Array(out[48..<48 + Int(size)])
    }

    /// Probe thông tin khóa (cmd 9): trả `(type4CC, dataSize)` hoặc nil nếu khóa không tồn tại.
    private func keyInfo(_ key: String) -> (type: String, size: Int)? {
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        let code = Self.fourCC(key)
        withUnsafeBytes(of: code) { inp.replaceSubrange(0..<4, with: $0) }
        inp[42] = 9 // kSMCReadKeyInfo
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        guard kr == KERN_SUCCESS && out[40] == 0 else { return nil }
        let sz = Int(Self.u32(out, 28))
        guard sz > 0 && sz <= 32 else { return nil }
        let type = String(bytes: out[32..<36], encoding: .ascii) ?? ""
        return (type, sz)
    }

    /// Đọc giá trị số của khóa, tự nhận kiểu dữ liệu thật (quan trọng cho Intel):
    ///   - `flt ` (4-byte float32) — fan keys trên Apple Silicon
    ///   - `fpe2` (2-byte 12.2 fixed) — fan keys trên Intel (F0Ac/F0Mn/F0Mx)
    ///   - `sp78` (2-byte 8.8 fixed) — vài cảm biến Intel
    /// Đọc sai kiểu (mặc định float32 cho mọi key) sẽ ra NaN/rác trên Intel → crash.
    func readFloat(key: String) -> Double {
        guard conn != 0, let info = keyInfo(key),
              let b = readBytes(key: key, size: UInt32(info.size)), b.count >= info.size else { return 0 }
        let value: Double
        if info.type == "flt " && info.size == 4 {
            let bits = b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            value = Double(Float(bitPattern: bits))
        } else if info.type == "sp78" && info.size == 2 {
            value = Double(Int8(bitPattern: b[0])) + Double(b[1]) / 256.0
        } else if info.size == 2 {
            // fpe2 (và fixed-point 2 byte khác) SMC là MSB-first: byte0 = phần cao.
            // F0Ac "12 bc" = 0x12bc/4 = 1199; decode little-endian sẽ đảo -> rác.
            let u = (UInt16(b[0]) << 8) | UInt16(b[1])
            value = Double(u) / 4.0
        } else if info.size == 4 {
            let bits = b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            value = Double(Float(bitPattern: bits))
        } else {
            value = 0
        }
        return value.isFinite && value >= 0 ? value : 0
    }

    func readFanCount() -> Int {
        guard conn != 0, let b = readBytes(key: "FNum", size: 1), let count = b.first else { return 0 }
        return Int(count)
    }

    /// Khoa co ton tai (kể ca khi gia tri = 0)? Phan biet "F0Md khong co" (MBA Intel)
    /// voi "F0Md ton tai = 0/1" (may co manual switch) — readFloat() tra 0 cho kieu ui8
    /// nen KHONG duoc suy su ton tai tu gia tri dem duoc (P1 review).
    func keyExists(_ key: String) -> Bool {
        keyInfo(key) != nil
    }
}

/// Điều khiển tốc độ quạt (Apple Silicon M1–M5 Air/Pro/Max/Ultra) theo kiểu iStat Menus:
/// System Controlled / Medium / High / thanh trượt thủ công.
/// Đọc trực tiếp qua IOKit AppleSMC (0 tiến trình con); ghi đồng bộ toàn bộ quạt qua helper `displaycontrol-power`.
@MainActor
public final class FanManager: ObservableObject {
    public static let shared = FanManager()

    public enum Mode: Equatable {
        case system
        case medium
        case high
        case manual
        case curve
    }

    nonisolated private static let requiredHelperVersion = PrivilegedHelper.requiredVersion
    nonisolated private static let helperPath = PrivilegedHelper.powerPath
    private static let safetyTempOn = 90.0
    private static let safetyTempOff = 80.0

    @Published public private(set) var fanCount: Int = 0
    @Published public private(set) var minRPM: Double = 0
    @Published public private(set) var maxRPM: Double = 0
    @Published public private(set) var currentRPM: Double = 0
    @Published public private(set) var mode: Mode = .system
    /// Tốc độ đích đang áp dụng (RPM) khi không ở System.
    @Published public private(set) var targetRPM: Double = 0
    @Published public private(set) var isHelperReady: Bool = false
    @Published public private(set) var isBusy: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var safetyTripped: Bool = false

    // ═ Fan Curve (nhiệt độ → % quạt, kiểu smcFanControl) ═
    @Published public private(set) var curveEnabled: Bool = false
    @Published public var curvePoints: [FanCurvePoint] = FanCurveMapper.defaults
    @Published public var curveTempSource: FanCurveTempSource = .cpuAverage
    private var lastCurveRpm: Double = -1
    nonisolated private static let curveEnabledKey = "hypermac.fanCurveEnabled"
    nonisolated private static let curvePointsKey = "hypermac.fanCurvePoints"
    nonisolated private static let curveSourceKey = "hypermac.fanCurveSource"


    // UI View State (Stored here to prevent CommandLineTools SwiftUIMacros @State crash)
    @Published public var sliderPercent: Double = 50
    @Published public var isDragging: Bool = false

    public var isAvailable: Bool { fanCount > 0 && maxRPM > 0 }

    private let smcReader = SMCFanReader()
    private var fanRanges: [(min: Double, max: Double)] = []
    private var verifyKey = "F0Tg"
    private var pollTimer: Timer?
    private var smcPath: String?
    private var pendingApply: DispatchWorkItem?
    private var isPopoverVisible = false

    public var needsSafetyMonitoring: Bool { isAvailable && (mode != .system || safetyTripped) }

    private init() {
        smcPath = FanManager.locateSMC()
        refreshStatic()
        refreshRPM()
        checkHelper()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        startPolling()
        // Khởi động luôn ở System: nếu bản trước crash giữa chừng, trả toàn bộ quạt về auto.
        if isAvailable { restoreAllFansAutoAsync() }
        // Fan curve: khôi phục cấu hình; nếu người dùng đang bật curve thì vào chế độ curve
        // (tick đầu tiên trong ~2.5s sẽ áp target theo nhiệt độ hiện tại).
        loadCurveConfig()
        if curveEnabled && isAvailable { mode = .curve }
    }

    // MARK: - Percent <-> RPM

    public func percent(forRPM rpm: Double) -> Int {
        // Guard NaN/Inf: `Int(Double.nan)` trap (SIGILL) khi mở thẻ quạt nếu RPM đọc ra rác.
        guard maxRPM > 0, rpm.isFinite, rpm >= 0 else { return 0 }
        return Int((rpm / maxRPM * 100).rounded())
    }

    public var minPercent: Int { min(percent(forRPM: minRPM), 100) }

    public func rpm(forPercent pct: Double) -> Double {
        let raw = maxRPM * pct / 100
        return min(max(raw, minRPM), maxRPM)
    }

    public var mediumRPM: Double { rpm(forPercent: 50) }
    public var highRPM: Double { rpm(forPercent: 80) }

    // MARK: - Public actions

    public func selectSystem() {
        pendingApply?.cancel()
        mode = .system
        targetRPM = 0
        errorMessage = nil
        restoreAllFansAutoAsync()
    }

    public func selectMedium() { apply(rpm: mediumRPM, as: .medium) }
    public func selectHigh() { apply(rpm: highRPM, as: .high) }

    /// Gọi liên tục khi kéo thanh trượt; debounce để không gọi sudo mỗi pixel.
    public func setManual(rpm: Double) {
        let clamped = min(max(rpm.rounded(), minRPM), maxRPM)
        mode = .manual
        targetRPM = clamped
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.apply(rpm: clamped, as: .manual) }
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    public func installHelperIfNeeded() {
        guard !isHelperReady else { return }
        BatteryManager.shared.installHelper { [weak self] _ in
            Task { @MainActor in self?.checkHelper() }
        }
    }

    /// Gọi khi thoát app (đồng bộ cho tất cả quạt 0..<fanCount).
    public func restoreSystemSync() {
        guard isAvailable else { return }
        let count = max(1, min(fanCount, 4))
        for i in 0..<count {
            _ = shell("sudo -n \(FanManager.helperPath) fan-auto \(i) \(naturalMinFor(i)) 2>/dev/null")
        }
        mode = .system
        targetRPM = 0
    }

    // MARK: - Internals

    private func restoreAllFansAutoAsync() {
        let count = max(1, min(fanCount, 4))
        let cmds = (0..<count).map { "sudo -n \(FanManager.helperPath) fan-auto \($0) \(naturalMinFor($0))" }.joined(separator: " && ")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell(cmds + " 2>&1")
        }
    }

    /// Min tu nhien cua quat i (P2: moi quat mot min rieng) — dung cho fan-auto restore.
    private func naturalMinFor(_ i: Int) -> Int { Int(i < fanRanges.count ? fanRanges[i].min : minRPM) }

    private func apply(rpm: Double, as newMode: Mode) {
        guard isAvailable else { return }
        guard !safetyTripped else {
            errorMessage = tr("Máy đang quá nóng, quạt do hệ thống điều khiển.",
                              "Mac is too hot; fan stays under system control.")
            return
        }
        // Không gate cứng theo isHelperReady (flag CÓ THỂ stale sau khi helper tự cập nhật):
        // để `sudo -n fan-set` là nguồn quyết định — chạy được thì chạy (đúng như cục gọi trực
        // tiếp đã verify), không chạy được thì rơi vào xử lý lỗi phía dưới (mode=.system + error).
        if !isHelperReady { checkHelper() }
        pendingApply?.cancel()
        mode = newMode
        targetRPM = rpm
        errorMessage = nil
        isBusy = true

        // Tính tỷ lệ phần trăm tốc độ và áp dụng đồng bộ cho TOÀN BỘ quạt (F0, F1... trên Pro/Max/Ultra)
        let ratio = maxRPM > 0 ? min(max(rpm / maxRPM, 0), 1) : 0.5
        let count = max(1, min(fanCount, 4))
        var subCommands: [String] = []
        let primaryValue = Int(min(max(rpm.rounded(), minRPM), maxRPM))

        for i in 0..<count {
            let range = i < fanRanges.count ? fanRanges[i] : (min: minRPM, max: maxRPM)
            let fanRpm = Int(min(max((range.max * ratio).rounded(), range.min), range.max))
            subCommands.append("sudo -n \(FanManager.helperPath) fan-set \(i) \(fanRpm)")
        }
        let fullCmd = subCommands.joined(separator: " && ") + " 2>&1"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (out, code) = shell(fullCmd)
            let ok = code == 0 && out.contains("FAN_SET_OK")
            if !ok { appLog("⚠️ Fan helper apply: code=\(code) \(out)") }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBusy = false
                if !ok {
                    self.mode = .system
                    self.targetRPM = 0
                    self.errorMessage = tr("Không đặt được tốc độ quạt trên máy này.",
                                           "Could not set fan speed on this Mac.")
                    return
                }
                // Ghi SMC có độ trễ: đọc lại sau ~1.5s rồi kiểm chứng.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.verifyTarget(expected: Double(primaryValue))
                }
            }
        }
    }

    private func verifyTarget(expected: Double) {
        guard mode != .system else { return }
        // MBA/Intel (no F0Md) ghi F0Mn; máy có F0Md ghi F0Tg — verify đúng key đã ghi.
        var tg = smcReader.readFloat(key: verifyKey)
        if tg <= 0, let smc = smcPath {
            let (out, _) = shell("'\(smc)' -k \(verifyKey) -r 2>/dev/null")
            tg = FanManager.parseFloat(out)
        }
        if abs(tg - expected) > 5 {
            self.mode = .system
            self.targetRPM = 0
            self.errorMessage = tr("macOS không giữ tốc độ quạt (đã trả về Tự động).",
                                   "macOS did not keep the fan speed (returned to Auto).")
            restoreAllFansAutoAsync()
        }
    }

    public func checkHelper() {
        let path = FanManager.helperPath
        let reqVer = FanManager.requiredHelperVersion
        DispatchQueue.global(qos: .utility).async {
            let (out, code) = shell("sudo -n \(path) version 2>/dev/null")
            var ver = 0
            if code == 0, let r = out.range(of: "HELPER_VERSION:") {
                ver = Int(out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber })) ?? 0
            }
            DispatchQueue.main.async {
                self.isHelperReady = ver >= reqVer
            }
        }
    }

    private func refreshStatic() {
        // 1. Đọc trực tiếp từ IOKit AppleSMC (0ms, không tạo tiến trình)
        var count = smcReader.readFanCount()
        if count == 0, let smc = smcPath {
            let (n, _) = shell("'\(smc)' -k FNum -r 2>/dev/null")
            count = Int(FanManager.parseFloat(n))
        }
        fanCount = count
        guard fanCount > 0 else { return }

        // F0Mn bi clamp TANG len khi fan-set -> doc song cho "min" sai (minRPM bi day len
        // theo lan clamp truoc, vi du crash giua chung). Persist min tu nhien NHO NHAT tung
        // thay cho TUNG QUAT (P2 review): moi fan mot key rieng. Clamp chi tang F0Mn nen
        // min(quan sat) = min thiet ke. Uu tien persisted thay vi doc song.
        var ranges: [(min: Double, max: Double)] = []
        for i in 0..<min(fanCount, 4) {
            var mn = smcReader.readFloat(key: "F\(i)Mn")
            var mx = smcReader.readFloat(key: "F\(i)Mx")
            if mx <= 0, let smc = smcPath {
                mn = FanManager.parseFloat(shell("'\(smc)' -k F\(i)Mn -r 2>/dev/null").0)
                mx = FanManager.parseFloat(shell("'\(smc)' -k F\(i)Mx -r 2>/dev/null").0)
            }
            if mx > 0 {
                let k = "hypermac.naturalFanMinRPM.\(i)"
                var nm = UserDefaults.standard.double(forKey: k)
                if nm <= 0 { nm = mn } else if mn > 0 && mn < nm { nm = mn }
                if nm > 0 { UserDefaults.standard.set(nm, forKey: k) }
                ranges.append((min: min(nm, mx), max: mx))
            }
        }
        fanRanges = ranges
        // P1 review: readFloat() khong doc duoc ui8 nen khong phan biet duoc F0Md=0 vs khong
        // co. Dung keyExists() phan loai: co F0Md -> verify F0Tg; khong co (MBA Intel) -> F0Mn.
        verifyKey = smcReader.keyExists("F0Md") ? "F0Tg" : "F0Mn"
        if let first = ranges.first {
            minRPM = first.min
            maxRPM = first.max
        }


    }

    private func refreshRPM() {
        guard fanCount > 0 else { return }
        // Đọc trực tiếp tất cả quạt (F0Ac, F1Ac...) qua IOKit AppleSMC — lấy trung bình RPM thực tế
        var total: Double = 0
        var validCount = 0
        for i in 0..<min(fanCount, 4) {
            let rpm = smcReader.readFloat(key: "F\(i)Ac")
            if rpm >= 0 {
                total += rpm
                validCount += 1
            }
        }
        if validCount > 0 {
            let avg = total / Double(validCount)
            if abs(avg - self.currentRPM) >= 5.0 || self.currentRPM == 0 {
                self.currentRPM = avg
            }
        } else if let smc = smcPath {
            DispatchQueue.global(qos: .utility).async {
                let rpm = FanManager.parseFloat(shell("'\(smc)' -k F0Ac -r 2>/dev/null").0)
                DispatchQueue.main.async {
                    if abs(rpm - self.currentRPM) >= 5.0 || self.currentRPM == 0 {
                        self.currentRPM = rpm
                    }
                }
            }
        }
    }

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible && fanCount > 0 {
            tick()
        }
        startPolling()
    }

    private func startPolling() {
        ThermalManager.shared.setFanThermalMonitorNeeded(needsSafetyMonitoring)
        guard fanCount > 0 else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        let shouldRun = isPopoverVisible || mode != .system || safetyTripped
        guard shouldRun else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    // MARK: - Fan curve (nhiệt độ → % quạt)

    public var curveLiveTemp: Double { curveTemperature() }
    public var curveLivePct: Double { FanCurveMapper.percent(for: curveTemperature(), curvePoints) }

    public func enableCurve() {
        guard isAvailable else { return }
        curveEnabled = true
        mode = .curve
        errorMessage = nil
        lastCurveRpm = -1
        applyCurve()
        startPolling()
        saveCurveConfig()
    }

    public func disableCurve() {
        curveEnabled = false
        lastCurveRpm = -1
        saveCurveConfig()
        selectSystem()
    }

    /// Ghi lại cấu hình curve (điểm + nguồn nhiệt + trạng thái bật) — gọi từ UI khi người dùng chỉnh.
    public func saveCurveConfig() {
        UserDefaults.standard.set(curveEnabled, forKey: Self.curveEnabledKey)
        UserDefaults.standard.set(curveTempSource.rawValue, forKey: Self.curveSourceKey)
        if let data = try? JSONEncoder().encode(curvePoints.sorted { $0.temp < $1.temp }) {
            UserDefaults.standard.set(data, forKey: Self.curvePointsKey)
        }
    }

    private func loadCurveConfig() {
        if let data = UserDefaults.standard.data(forKey: Self.curvePointsKey),
           let pts = try? JSONDecoder().decode([FanCurvePoint].self, from: data), !pts.isEmpty {
            curvePoints = pts
        } else {
            curvePoints = FanCurveMapper.defaults
        }
        curveTempSource = FanCurveTempSource(rawValue: UserDefaults.standard.integer(forKey: Self.curveSourceKey)) ?? .cpuAverage
        curveEnabled = UserDefaults.standard.bool(forKey: Self.curveEnabledKey)
        if curvePoints.isEmpty { curvePoints = FanCurveMapper.defaults }
    }

    private func curveTemperature() -> Double {
        let t = ThermalManager.shared
        switch curveTempSource {
        case .cpuAverage: return max(t.cpuAvgTemp, 0)
        case .cpuPeak:    return max(t.cpuPeakTemp, 0)
        case .hotspot:    return max(t.hotspotTemp, 0)
        }
    }

    /// Áp dụng target theo nhiệt độ hiện tại (kiểu smcFanControl). Gọi từ tick() khi đang bật curve.
    private func applyCurve() {
        guard isAvailable, curveEnabled, mode == .curve, !safetyTripped else { return }
        let pct = FanCurveMapper.percent(for: curveTemperature(), curvePoints)
        let rpmVal = rpm(forPercent: pct)
        // Throttle: chỉ ghi khi nhiệt thay đổi đủ lớn (tránh sudo mỗi 2.5s).
        let delta = abs(rpmVal - lastCurveRpm)
        if lastCurveRpm < 0 || delta > 40 {
            lastCurveRpm = rpmVal
            apply(rpm: rpmVal, as: .curve)
        }
    }

    private func tick() {
        refreshRPM()
        enforceSafety()
        if curveEnabled && mode == .curve && isAvailable && !safetyTripped {
            applyCurve()
        }
        ThermalManager.shared.setFanThermalMonitorNeeded(needsSafetyMonitoring)
    }

    /// Ngưỡng an toàn: CPU/GPU >= 90°C thì ép về System, mở lại khi < 80°C.
    private func enforceSafety() {
        let t = ThermalManager.shared
        let hottest = max(t.cpuPeakTemp, t.gpuAvgTemp, t.hotspotTemp)
        if !safetyTripped, hottest >= FanManager.safetyTempOn {
            safetyTripped = true
            if mode != .system {
                selectSystem()
                errorMessage = tr("Quá nóng (≥90°C): đã trả quạt về hệ thống.",
                                  "Too hot (≥90°C): fan returned to system control.")
            }
        } else if safetyTripped, hottest < FanManager.safetyTempOff {
            safetyTripped = false
            errorMessage = nil
        }
    }

    @objc private func willSleep() { if mode != .system { selectSystem() } }
    @objc private func didWake() { checkHelper(); refreshRPM() }

    // MARK: - Helpers

    private static func locateSMC() -> String? {
        let candidates = [
            Bundle.main.path(forResource: "smc", ofType: nil),
            PrivilegedHelper.smcPath
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Phân tích dòng `  F0Ac  [flt ]  2985 (bytes ...)` hoặc `[ui8 ]  1 (...)` → số.
    nonisolated static func parseFloat(_ s: String) -> Double {
        guard let close = s.range(of: "]") else { return 0 }
        let rest = s[close.upperBound...].trimmingCharacters(in: .whitespaces)
        let token = rest.split(separator: " ").first.map(String.init) ?? ""
        return Double(token) ?? 0
    }
}
