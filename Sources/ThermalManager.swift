import Foundation
import IOKit
import AppKit

// MARK: - Sensor Model

public struct SensorReading: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let temp: Double
    public let category: String
}

// MARK: - Native Apple Silicon IOHID Temperature Reader

private typealias FnCreateWithType = @convention(c) (CFAllocator?, UInt32, CFDictionary?) -> Unmanaged<CFTypeRef>?
private typealias FnCopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
private typealias FnCopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
private typealias FnCopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
private typealias FnGetFloat = @convention(c) (CFTypeRef, UInt32) -> Double

private class AppleSiliconHIDReader {
    private var client: CFTypeRef?
    private var cachedServices: [(service: CFTypeRef, name: String)] = []
    private var lastDiscoveryTime: TimeInterval = 0

    private var fnCreate: FnCreateWithType?
    private var fnCopyServices: FnCopyServices?
    private var fnCopyProperty: FnCopyProperty?
    private var fnCopyEvent: FnCopyEvent?
    private var fnGetFloat: FnGetFloat?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        if let s = dlsym(handle, "IOHIDEventSystemClientCreateWithType") { fnCreate = unsafeBitCast(s, to: FnCreateWithType.self) }
        if let s = dlsym(handle, "IOHIDEventSystemClientCopyServices") { fnCopyServices = unsafeBitCast(s, to: FnCopyServices.self) }
        if let s = dlsym(handle, "IOHIDServiceClientCopyProperty") { fnCopyProperty = unsafeBitCast(s, to: FnCopyProperty.self) }
        if let s = dlsym(handle, "IOHIDServiceClientCopyEvent") { fnCopyEvent = unsafeBitCast(s, to: FnCopyEvent.self) }
        if let s = dlsym(handle, "IOHIDEventGetFloatValue") { fnGetFloat = unsafeBitCast(s, to: FnGetFloat.self) }
    }

    func readTemperatures() -> (cpuAvg: Double, cpuPeak: Double, gpuAvg: Double, battery: Double, nand: Double, hotspot: Double, sensors: [SensorReading]) {
        guard let create = fnCreate, let copyServ = fnCopyServices, let copyProp = fnCopyProperty,
              let copyEvt = fnCopyEvent, let getFloat = fnGetFloat else {
            return (0, 0, 0, 0, 0, 0, [])
        }

        let now = ProcessInfo.processInfo.systemUptime
        if client == nil {
            client = create(kCFAllocatorDefault, 1, nil)?.takeRetainedValue()
        }
        guard let c = client else { return (0, 0, 0, 0, 0, 0, []) }

        // Refresh services every 60s (using takeRetainedValue so CFArray & CFString never leak!)
        if cachedServices.isEmpty || (now - lastDiscoveryTime > 60) {
            cachedServices.removeAll(keepingCapacity: true)
            if let servCF = copyServ(c)?.takeRetainedValue() {
                let count = CFArrayGetCount(servCF)
                for i in 0..<count {
                    guard let rawPtr = CFArrayGetValueAtIndex(servCF, i) else { continue }
                    let s = Unmanaged<CFTypeRef>.fromOpaque(rawPtr).takeUnretainedValue()
                    // Chỉ giữ cảm biến được dùng bên dưới (CPU/GPU/pin/SSD/bo mạch): mỗi lần đọc
                    // gọi CopyEvent cho ~57 thay vì ~140 service.
                    if let nameRef = copyProp(s, "Product" as CFString)?.takeRetainedValue(),
                       let name = nameRef as? String, Self.isUsedSensor(name) {
                        cachedServices.append((service: s, name: name))
                    }
                }
            }
            lastDiscoveryTime = now
        }

        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        var batteryTemps: [Double] = []
        var nandTemps: [Double] = []
        var hotspotTemps: [Double] = []
        var sensorList: [SensorReading] = []

        let kIOHIDEventTypeTemperature: Int64 = 15
        let kIOHIDEventFieldTemperatureValue: UInt32 = (15 << 16) | 0

        for item in cachedServices {
            let s = item.service
            let name = item.name

            // takeRetainedValue() ensures ARC releases every IOHIDEvent at the end of each loop iteration!
            guard let evt = copyEvt(s, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() else { continue }
            let temp = getFloat(evt, kIOHIDEventFieldTemperatureValue)
            guard temp > 15.0 && temp < 125.0 else { continue }

            if name.hasPrefix("PMU tdie") || name.hasPrefix("PMU2 tdie") {
                cpuTemps.append(temp)
                let coreIdx = name.replacingOccurrences(of: "PMU tdie", with: "").replacingOccurrences(of: "PMU2 tdie", with: " (P-Core ")
                let label = name.contains("PMU2") ? "CPU P-Core \(coreIdx.replacingOccurrences(of: " (P-Core ", with: ""))" : "CPU Core \(coreIdx)"
                sensorList.append(SensorReading(name: name, displayName: label, temp: temp, category: "CPU"))
            } else if name.hasPrefix("PMU tdev") || name.hasPrefix("PMU2 tdev") {
                gpuTemps.append(temp)
                let gpuIdx = name.replacingOccurrences(of: "PMU tdev", with: "").replacingOccurrences(of: "PMU2 tdev", with: " ")
                sensorList.append(SensorReading(name: name, displayName: tr("GPU Cụm \(gpuIdx)", "GPU Cluster \(gpuIdx)"), temp: temp, category: "GPU"))
            } else if name.contains("battery") {
                batteryTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: tr("Pin Cell (Gas Gauge)", "Battery Cell (Gas Gauge)"), temp: temp, category: tr("Pin", "Battery")))
            } else if name.contains("NAND") {
                nandTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: "SSD NVMe Flash", temp: temp, category: tr("Ổ cứng", "Storage")))
            } else if name.contains("tcal") {
                hotspotTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: tr("Hotspot Bo mạch", "Logic Board Hotspot"), temp: temp, category: tr("Bo mạch", "Logic Board")))
            }
        }

        let cpuAvg = cpuTemps.isEmpty ? 0.0 : (cpuTemps.reduce(0, +) / Double(cpuTemps.count))
        let cpuPeak = cpuTemps.max() ?? 0.0
        let gpuAvg = gpuTemps.isEmpty ? 0.0 : (gpuTemps.reduce(0, +) / Double(gpuTemps.count))
        let bat = batteryTemps.isEmpty ? 0.0 : (batteryTemps.reduce(0, +) / Double(batteryTemps.count))
        let nand = nandTemps.isEmpty ? 0.0 : (nandTemps.reduce(0, +) / Double(nandTemps.count))
        let hot = hotspotTemps.isEmpty ? 0.0 : (hotspotTemps.reduce(0, +) / Double(hotspotTemps.count))

        return (cpuAvg, cpuPeak, gpuAvg, bat, nand, hot, sensorList)
    }

    private static func isUsedSensor(_ name: String) -> Bool {
        name.hasPrefix("PMU tdie") || name.hasPrefix("PMU2 tdie") ||
            name.hasPrefix("PMU tdev") || name.hasPrefix("PMU2 tdev") ||
            name.contains("battery") || name.contains("NAND") || name.contains("tcal")
    }

    deinit {
        cachedServices.removeAll()
        client = nil
    }
}

// MARK: - AppleSMC Core Temperature Reader

private struct SMCSensorKey {
    enum Group { case cpu, gpu, battery, nand, hotspot }
    let code: UInt32
    let name: String
    let label: String
    let group: Group
}

/// Đọc nhiệt độ nhân CPU/GPU thật từ AppleSMC (kiểu `flt `) — cùng nguồn với Macs Fan Control / Stats.
/// Chỉ đọc đúng danh sách khóa cảm biến nhân đã được xác minh cho từng đời chip M1–M5
/// (theo bảng `exelban/stats`), KHÔNG quét mọi khóa `Tp*`: trên M2, các khóa như
/// `Tp02/Tp06/Tp0A/Tp0E/Tp0g/Tp0k/Tp0o/Tp0s` không phải nhân CPU và luôn cao hơn 15–20°C,
/// làm "CPU nóng nhất" bị vọt ảo.
/// Không cần root. Bố cục struct 80 byte theo `SMCKeyData_t` của smc.c.
private final class SMCTempReader {
    private var conn: io_connect_t = 0
    private var keys: [SMCSensorKey]?   // nil = chưa dò
    private var lastGood: [UInt32: Double] = [:]

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

    /// cmd: 5 = đọc giá trị, 8 = lấy khóa theo chỉ số, 9 = lấy thông tin khóa.
    private func call(cmd: UInt8, key: UInt32 = 0, index: UInt32 = 0, size: UInt32 = 0) -> [UInt8]? {
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        withUnsafeBytes(of: key) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = cmd
        withUnsafeBytes(of: index) { inp.replaceSubrange(44..<48, with: $0) }
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        return kr == KERN_SUCCESS && out[40] == 0 ? out : nil
    }

    /// Đời chip Apple Silicon từ `machdep.cpu.brand_string` ("Apple M2", "Apple M3 Max"...). 0 = không rõ.
    private static func chipGeneration() -> Int {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = String(cString: buf)
        guard let r = brand.range(of: "Apple M") else { return 0 }
        return Int(brand[r.upperBound...].prefix(while: { $0.isNumber })) ?? 0
    }

    /// Bảng khóa cảm biến nhân đã xác minh theo từng đời chip (nguồn: exelban/stats `values.swift`).
    /// Khóa không tồn tại trên biến thể cụ thể (Air/Pro/Max/Ultra) sẽ tự bị bỏ qua lúc dò.
    private static func catalog(for gen: Int) -> (cpu: [(key: String, label: String)], gpu: [String]) {
        func cores(_ keys: [String], _ kind: String) -> [(key: String, label: String)] {
            keys.enumerated().map { (key: $0.element, label: "CPU \(kind) \($0.offset + 1)") }
        }
        switch gen {
        case 1:
            return (cores(["Tp09", "Tp0T"], "E-Core") +
                    cores(["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"], "P-Core"),
                    ["Tg05", "Tg0D", "Tg0L", "Tg0T"])
        case 2:
            return (cores(["Tp1h", "Tp1t", "Tp1p", "Tp1l"], "E-Core") +
                    cores(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], "P-Core"),
                    ["Tg0f", "Tg0j"])
        case 3:
            return (cores(["Te05", "Te0L", "Te0P", "Te0S"], "E-Core") +
                    cores(["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                           "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"], "P-Core"),
                    ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"])
        case 4:
            return (cores(["Te05", "Te0S", "Te09", "Te0H"], "E-Core") +
                    cores(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"], "P-Core"),
                    ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"])
        case 5:
            return (cores(["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"], "Super-Core") +
                    cores(["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
                           "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"], "P-Core"),
                    ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"])
        default:
            // Đời chip chưa được xác minh → không đoán bừa, để HID làm dự phòng.
            return ([], [])
        }
    }

    private func discover() -> [SMCSensorKey] {
        let flt = Self.fourCC("flt ")
        func probe(_ name: String, _ label: String, _ group: SMCSensorKey.Group) -> SMCSensorKey? {
            let code = Self.fourCC(name)
            guard let info = call(cmd: 9, key: code),
                  Self.u32(info, 28) == 4, Self.u32(info, 32) == flt else { return nil }
            return SMCSensorKey(code: code, name: name, label: label, group: group)
        }

        let cat = Self.catalog(for: Self.chipGeneration())
        var found: [SMCSensorKey] = cat.cpu.compactMap { probe($0.key, $0.label, .cpu) }
        var gpuIndex = 0
        for key in cat.gpu {
            if let k = probe(key, "GPU \(gpuIndex + 1)", .gpu) {
                found.append(k)
                gpuIndex += 1
            }
        }
        if let k = probe("TB0T", "Battery", .battery) { found.append(k) }
        if let k = probe("TH0x", "NAND", .nand) { found.append(k) }
        if let k = probe("TW0P", "Airport", .hotspot) { found.append(k) }
        if let k = probe("TPMP", "PMU", .hotspot) { found.append(k) }
        return found
    }

    /// Đọc nhiệt độ CPU, GPU và cảm biến phụ trợ từ SMC (hỗ trợ M1–M5 Air/Pro/Max/Ultra).
    func read() -> (cpu: [SensorReading], gpu: [SensorReading], battery: Double, nand: Double, hotspot: Double) {
        if keys == nil { keys = discover() }
        var cpu: [SensorReading] = [], gpu: [SensorReading] = []
        var bat: Double = 0, nand: Double = 0, hot: Double = 0

        for k in keys ?? [] {
            var sample: Double?
            if let v = call(cmd: 5, key: k.code, size: 4) {
                let raw = Double(Float(bitPattern: Self.u32(v, 48)))
                if raw >= 10.0 && raw < 120.0 { sample = raw }
            }
            // Cảm biến M2 thỉnh thoảng trả 0 / giá trị rác → giữ giá trị hợp lệ gần nhất (giống Stats).
            if let sample { lastGood[k.code] = sample }
            guard let t = sample ?? lastGood[k.code] else { continue }

            switch k.group {
            case .cpu:
                cpu.append(SensorReading(name: k.name, displayName: "\(k.label) (\(k.name))", temp: t, category: "CPU"))
            case .gpu:
                gpu.append(SensorReading(name: k.name, displayName: "\(k.label) (\(k.name))", temp: t, category: "GPU"))
            case .battery:
                bat = t
            case .nand:
                nand = t
            case .hotspot:
                hot = max(hot, t)
            }
        }
        return (cpu, gpu, bat, nand, hot)
    }
}

// MARK: - Thermal Manager Engine (Temperature Monitoring Only)

/// Reads Apple Silicon HID/PMU temperature sensors and exposes them to the UI.
///
/// NOTE: Fan control was intentionally removed in v1.5.2. HyperMac no longer
/// writes SMC fan keys or installs a privileged helper for fan speed changes.
@MainActor
public class ThermalManager: ObservableObject {
    public static let shared = ThermalManager()

    @Published public var machineModelName: String = "Mac"

    // Real-Time Temperatures (°C)
    @Published public var cpuAvgTemp: Double = 0.0
    @Published public var cpuPeakTemp: Double = 0.0
    @Published public var gpuAvgTemp: Double = 0.0
    @Published public var batteryTemp: Double = 0.0
    @Published public var ssdTemp: Double = 0.0
    @Published public var hotspotTemp: Double = 0.0

    // Detailed Sensor Breakdown
    @Published public var detailedSensors: [SensorReading] = []
    @Published public var isDetailExpanded: Bool = false

    // UI View State (Stored here to prevent CommandLineTools SwiftUIMacros @State crash)
    @Published public var selectedSection: Int = 0 // 0: Pin & Nguồn SMC, 1: Nhiệt độ & Cảm biến
    @Published public var isRefreshing: Bool = false

    // Thermal Throttling & Status
    @Published public var thermalStateDescription: String = "Mát mẻ (Bình thường)"
    @Published public var isThrottling: Bool = false

    // Menu Bar live temperature pill
    @Published public var showMenuBarMetrics: Bool = UserDefaults.standard.bool(forKey: "show_menubar_thermal") {
        didSet {
            UserDefaults.standard.set(showMenuBarMetrics, forKey: "show_menubar_thermal")
            updateMenuBarDisplay()
            updatePolling()
        }
    }
    public var onMenuBarUpdate: ((String?) -> Void)?

    private let hidReader = AppleSiliconHIDReader()
    private let smcReader = SMCTempReader()
    private var pollTimer: Timer?
    /// Ai đang cần số liệu: popover đang mở, quạt đang chỉnh tay (ngưỡng an toàn 90°C), hoặc
    /// nhiệt độ hiện trên menu bar. Không ai cần thì không đọc cảm biến.
    private var isPopoverVisible = false
    private var isFanSafetyActive = false

    /// Ngưỡng trạng thái tính theo CPU TRUNG BÌNH (không theo 1 nhân đỉnh tức thời).
    /// Apple Silicon: dùng nhẹ ~40–65°C, tải vừa 65–85°C, tải nặng > 85°C (giảm xung ~100°C+).
    public static let warmThreshold: Double = 65.0
    public static let hotThreshold: Double = 85.0

    /// Hệ số làm mượt EMA (mẫu 2.5s) — lọc gai nhiệt tức thời khi 1 nhân vừa thức dậy vài mili-giây.
    private static let emaAlpha: Double = 0.4

    /// Nhiệt độ đại diện để hiển thị trên badge / Menu Bar: CPU trung bình.
    public var displayTemp: Double { cpuAvgTemp > 0 ? cpuAvgTemp : cpuPeakTemp }

    public enum ThermalLevel { case cool, warm, hot }
    public var thermalLevel: ThermalLevel {
        let t = displayTemp
        if t < Self.warmThreshold { return .cool }
        if t < Self.hotThreshold { return .warm }
        return .hot
    }

    private func smooth(_ previous: Double, _ sample: Double) -> Double {
        guard previous > 0 else { return sample }
        return previous + Self.emaAlpha * (sample - previous)
    }

    private init() {
        loadMachineHardwareInfo()
        refreshMetrics()
        updatePolling()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    private func loadMachineHardwareInfo() {
        // 1. Try reading exact Apple Silicon marketing name from IODeviceTree:/product ("product-name")
        let productEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if productEntry != 0 {
            defer { IOObjectRelease(productEntry) }
            if let prop = IORegistryEntryCreateCFProperty(productEntry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               let name = String(data: prop, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\n")),
               !name.isEmpty {
                // Strip parenthetical year/size if desired or keep concise family + chip
                if let parenIdx = name.firstIndex(of: "(") {
                    let baseName = String(name[..<parenIdx]).trimmingCharacters(in: .whitespaces)
                    if !baseName.isEmpty {
                        self.machineModelName = baseName
                        return
                    }
                }
                self.machineModelName = name
                return
            }
        }

        // 2. Fallback to sysctl hw.model mapping (M1–M5 Air, Pro, Max, Ultra)
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        let modelLower = modelString.lowercased()

        if modelLower.contains("air") ||
            modelString.hasPrefix("Mac14,2") || modelString.hasPrefix("Mac14,15") ||
            modelString.hasPrefix("Mac15,12") || modelString.hasPrefix("Mac15,13") ||
            modelString.hasPrefix("Mac16,12") || modelString.hasPrefix("Mac16,13") {
            self.machineModelName = "MacBook Air"
        } else if modelString.hasPrefix("MacBook8,") ||
                    modelString.hasPrefix("MacBook9,") ||
                    modelString.hasPrefix("MacBook10,") {
            self.machineModelName = "MacBook (12-inch)"
        } else if modelLower.contains("mini") || modelString == "Mac14,3" || modelString == "Mac14,12" ||
                    modelString.hasPrefix("Mac16,10") || modelString.hasPrefix("Mac16,11") || modelString.hasPrefix("Mac16,15") {
            self.machineModelName = "Mac mini"
        } else if modelLower.contains("studio") || modelString.hasPrefix("Mac13,") ||
                    modelString == "Mac14,13" || modelString == "Mac14,14" ||
                    modelString == "Mac15,14" || modelString == "Mac16,9" {
            self.machineModelName = "Mac Studio"
        } else if modelString == "Mac14,8" {
            self.machineModelName = "Mac Pro"
        } else if modelLower.contains("imac") || modelString == "Mac15,4" || modelString == "Mac15,5" ||
                    modelString == "Mac16,2" || modelString == "Mac16,3" {
            self.machineModelName = "iMac"
        } else if modelLower.contains("pro") ||
                    modelString.hasPrefix("MacBookPro") ||
                    modelString.hasPrefix("Mac14,") ||
                    modelString.hasPrefix("Mac15,") ||
                    modelString.hasPrefix("Mac16,") ||
                    modelString.hasPrefix("Mac17,") {
            self.machineModelName = "MacBook Pro"
        } else {
            self.machineModelName = modelString.isEmpty ? "Mac" : modelString
        }
    }

    // MARK: - Polling & Refresh Metrics

    public func setPopoverVisible(_ visible: Bool) {
        guard visible != isPopoverVisible else { return }
        isPopoverVisible = visible
        if visible { refreshMetrics() }
        updatePolling()
    }

    func setFanSafetyActive(_ active: Bool) {
        guard active != isFanSafetyActive else { return }
        isFanSafetyActive = active
        updatePolling()
    }

    /// 2,5 s khi popover mở hoặc quạt chỉnh tay; 5 s khi chỉ hiện nhiệt độ trên menu bar; dừng hẳn
    /// khi không ai cần.
    private func updatePolling() {
        let interval: TimeInterval
        if isPopoverVisible || isFanSafetyActive {
            interval = 2.5
        } else if showMenuBarMetrics {
            interval = 5.0
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        if let pollTimer, pollTimer.isValid, pollTimer.timeInterval == interval { return }
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }
        timer.tolerance = interval * 0.2  // cho macOS gộp lần thức với việc khác
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func refreshMetrics() {
        // 1. Read Apple Silicon HID Temperatures
        var (cpu, peak, gpu, bat, nand, hot, sensors) = hidReader.readTemperatures()

        // CPU/GPU: ưu tiên SMC (nhiệt nhân thật trên M1–M5 Air/Pro/Max/Ultra); HID PMU là dự phòng.
        let smc = smcReader.read()
        if !smc.cpu.isEmpty {
            let t = smc.cpu.map(\.temp)
            cpu = t.reduce(0, +) / Double(t.count)
            peak = t.max() ?? 0
            sensors.removeAll { $0.category == "CPU" }
        }
        if !smc.gpu.isEmpty {
            gpu = smc.gpu.map(\.temp).reduce(0, +) / Double(smc.gpu.count)
            sensors.removeAll { $0.category == "GPU" }
        }
        if bat <= 0 && smc.battery > 0 { bat = smc.battery }
        if nand <= 0 && smc.nand > 0 { nand = smc.nand }
        if hot <= 0 && smc.hotspot > 0 { hot = smc.hotspot }

        sensors = smc.cpu + smc.gpu + sensors
        if cpu > 0 { self.cpuAvgTemp = smooth(self.cpuAvgTemp, cpu) }
        if peak > 0 { self.cpuPeakTemp = smooth(self.cpuPeakTemp, peak) }
        if gpu > 0 { self.gpuAvgTemp = smooth(self.gpuAvgTemp, gpu) }
        if bat > 0 { self.batteryTemp = bat }
        if nand > 0 { self.ssdTemp = nand }
        if hot > 0 { self.hotspotTemp = hot }
        if !sensors.isEmpty { self.detailedSensors = sensors }

        // 2. Read System Thermal Pressure
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal, .fair:
            switch thermalLevel {
            case .cool: self.thermalStateDescription = tr("Mát mẻ (Bình thường)", "Cool (Normal)")
            case .warm: self.thermalStateDescription = tr("Ấm (Tải vừa)", "Warm (Moderate)")
            case .hot:  self.thermalStateDescription = tr("Nóng (Chưa giảm xung)", "Hot (Not throttling)")
            }
            self.isThrottling = false
        case .serious:
            self.thermalStateDescription = tr("Nóng (Đang giảm xung nhẹ)", "Hot (Slight Throttling)")
            self.isThrottling = true
        case .critical:
            self.thermalStateDescription = tr("Rất nóng (Thermal Throttling tối đa!)", "Critical (Heavy Throttling!)")
            self.isThrottling = true
        @unknown default:
            self.thermalStateDescription = tr("Bình thường", "Normal")
            self.isThrottling = false
        }

        // 3. Update Menu Bar Live Telemetry
        updateMenuBarDisplay()
    }

    @objc private func thermalStateChanged() {
        refreshMetrics()
    }

    public func updateMenuBarDisplay() {
        guard showMenuBarMetrics else {
            onMenuBarUpdate?(nil)
            return
        }
        let temp = Int(displayTemp.rounded())
        guard temp > 0 else {
            onMenuBarUpdate?(nil)
            return
        }
        onMenuBarUpdate?("\(temp)°C")
    }
}
