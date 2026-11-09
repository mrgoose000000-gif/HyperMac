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

    func readFanCount() -> Int {
        guard let b = readBytes(key: "FNum", size: 1), let count = b.first else { return 0 }
        return Int(count)
    }

    func readFloat(key: String) -> Double {
        guard let b = readBytes(key: key, size: 4), b.count == 4 else { return 0 }
        let bits = b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let val = Double(Float(bitPattern: bits))
        return val.isFinite && val >= 0 ? val : 0
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
    }

    nonisolated private static let requiredHelperVersion = 2
    nonisolated private static let helperPath = "/usr/local/bin/displaycontrol-power"
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

    // UI View State (Stored here to prevent CommandLineTools SwiftUIMacros @State crash)
    @Published public var sliderPercent: Double = 50
    @Published public var isDragging: Bool = false

    public var isAvailable: Bool { fanCount > 0 && maxRPM > 0 }

    private let smcReader = SMCFanReader()
    private var fanRanges: [(min: Double, max: Double)] = []
    private var pollTimer: Timer?
    private var smcPath: String?
    private var pendingApply: DispatchWorkItem?

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
    }

    // MARK: - Percent <-> RPM

    public func percent(forRPM rpm: Double) -> Int {
        guard maxRPM > 0 else { return 0 }
        return Int((rpm / maxRPM * 100).rounded())
    }

    public var minPercent: Int { percent(forRPM: minRPM) }

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
            _ = shell("sudo -n \(FanManager.helperPath) fan-auto \(i) 2>/dev/null")
        }
        mode = .system
        targetRPM = 0
    }

    // MARK: - Internals

    private func restoreAllFansAutoAsync() {
        let count = max(1, min(fanCount, 4))
        let cmds = (0..<count).map { "sudo -n \(FanManager.helperPath) fan-auto \($0)" }.joined(separator: " && ")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell(cmds + " 2>&1")
        }
    }

    private func apply(rpm: Double, as newMode: Mode) {
        guard isAvailable else { return }
        guard !safetyTripped else {
            errorMessage = tr("Máy đang quá nóng, quạt do hệ thống điều khiển.",
                              "Mac is too hot; fan stays under system control.")
            return
        }
        guard isHelperReady else {
            errorMessage = tr("Cần cài helper (hỏi mật khẩu quản trị một lần).",
                              "Helper install needed (one admin password prompt).")
            mode = .system
            return
        }
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
        var tg = smcReader.readFloat(key: "F0Tg")
        if tg <= 0, let smc = smcPath {
            let (out, _) = shell("'\(smc)' -k F0Tg -r 2>/dev/null")
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

        var ranges: [(min: Double, max: Double)] = []
        for i in 0..<min(fanCount, 4) {
            var mn = smcReader.readFloat(key: "F\(i)Mn")
            var mx = smcReader.readFloat(key: "F\(i)Mx")
            if mx <= 0, let smc = smcPath {
                mn = FanManager.parseFloat(shell("'\(smc)' -k F\(i)Mn -r 2>/dev/null").0)
                mx = FanManager.parseFloat(shell("'\(smc)' -k F\(i)Mx -r 2>/dev/null").0)
            }
            if mx > 0 {
                ranges.append((min: mn, max: mx))
            }
        }
        fanRanges = ranges
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
            self.currentRPM = total / Double(validCount)
        } else if let smc = smcPath {
            DispatchQueue.global(qos: .utility).async {
                let rpm = FanManager.parseFloat(shell("'\(smc)' -k F0Ac -r 2>/dev/null").0)
                DispatchQueue.main.async { self.currentRPM = rpm }
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        guard fanCount > 0 else { return } // Không chạy timer vô ích trên MacBook Air không quạt
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        refreshRPM()
        enforceSafety()
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
            "/usr/local/bin/displaycontrol-smc",
            FileManager.default.currentDirectoryPath + "/Resources/smc"
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
