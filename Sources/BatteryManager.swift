import Foundation
import IOKit
import Combine
import AppKit

// MARK: - Native Apple Silicon PowerUI Client (macOS 15+ / Sequoia & Modern Firmware)

@MainActor
public final class NativePowerUIClient {
    public static let shared = NativePowerUIClient()

    private var clientInstance: NSObject?
    public private(set) var isSupported: Bool = false

    private init() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/PowerUI.framework"), bundle.load() else {
            return
        }
        guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else {
            return
        }
        let selInit = NSSelectorFromString("initWithClientName:")
        guard cls.instancesRespond(to: selInit),
              let client = cls.init().perform(selInit, with: "HyperMac")?.takeUnretainedValue() as? NSObject else {
            return
        }
        self.clientInstance = client

        let selSupported = NSSelectorFromString("isMCLSupported")
        if client.responds(to: selSupported) {
            typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
            let fn = unsafeBitCast(client.method(for: selSupported), to: BoolFn.self)
            self.isSupported = fn(client, selSupported)
        }
    }

    public func setLimit(_ limit: Int) -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selSet = NSSelectorFromString("setMCLLimit:error:")
        guard client.responds(to: selSet) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>?) -> Bool
        var err: NSError? = nil
        let ok = unsafeBitCast(client.method(for: selSet), to: SetFn.self)(client, selSet, UInt8(min(max(limit, 50), 100)), &err)
        if !ok || err != nil {
            appLog("⚠️ NativePowerUIClient: setMCLLimit(\(limit)) failed: \(String(describing: err))")
            return false
        }
        appLog("🔋 NativePowerUIClient: setMCLLimit(\(limit)) succeeded")
        return true
    }

    public func disable() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selDisable = NSSelectorFromString("disableMCL:")
        guard client.responds(to: selDisable) else { return false }
        typealias DisableFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        var err: NSError? = nil
        let ok = unsafeBitCast(client.method(for: selDisable), to: DisableFn.self)(client, selDisable, &err)
        if !ok || err != nil {
            appLog("⚠️ NativePowerUIClient: disableMCL failed: \(String(describing: err))")
            return false
        }
        appLog("🔋 NativePowerUIClient: disableMCL succeeded (charging restored)")
        return true
    }

    public func isCurrentlyEnabled() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selEnabled = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard client.responds(to: selEnabled) else { return false }
        typealias BoolErrFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt64
        var err: NSError? = nil
        let res = unsafeBitCast(client.method(for: selEnabled), to: BoolErrFn.self)(client, selEnabled, &err)
        return res != 0
    }

    public func currentLimit() -> Int {
        guard isSupported, let client = clientInstance else { return 100 }
        let selGet = NSSelectorFromString("getMCLLimitWithError:")
        guard client.responds(to: selGet) else { return 100 }
        typealias UcharErrFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt8
        var err: NSError? = nil
        let limit = unsafeBitCast(client.method(for: selGet), to: UcharErrFn.self)(client, selGet, &err)
        return Int(limit)
    }
}

// MARK: - Battery Manager (Hardware Care & Longevity)

@MainActor
public class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    // MARK: - Published State
    @Published public var currentLevel: Int = 0
    @Published public var maxCapacityPercent: Int = 100
    @Published public var nominalCapacity: Int = 0
    @Published public var designCapacity: Int = 0
    @Published public var healthPercent: Int = 100
    @Published public var exactHealthPercent: Double = 100.0
    @Published public var cycleCount: Int = 0
    @Published public var temperature: Double = 0.0      // in °C
    @Published public var voltage: Double = 0.0          // in Volts
    @Published public var amperage: Int = 0              // in mA
    @Published public var wattage: Double = 0.0          // in Watts
    @Published public var isPluggedIn: Bool = false
    @Published public var isCharging: Bool = false
    @Published public var isFullyCharged: Bool = false
    @Published public var timeRemaining: Int = 0         // in minutes
    @Published public var isBypassActive: Bool = false    // SMC CHTE = 1 (Running direct from AC)
    @Published public var isHelperInstalled: Bool = false
    @Published public var isInstallingHelper: Bool = false
    @Published public var statusMessage: String = "Đang kiểm tra..."
    @Published public var lastUpdated: Date = Date()

    // Extended Telemetry
    @Published public var adapterWatts: Int = 0          // e.g. 30W
    @Published public var adapterDescription: String = "" // e.g. "pd charger"
    @Published public var adapterSerial: String = ""
    @Published public var batterySerial: String = ""
    @Published public var gasGaugeChip: String = ""

    // User Settings (Stored in UserDefaults)
    @Published public var isProtectionEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "battery_protection_enabled")
            evaluatePowerManagement()
        }
    }

    @Published public var chargeLimit: Int = 80 {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "battery_charge_limit")
            evaluatePowerManagement()
        }
    }

    @Published public var isTopUpActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isTopUpActive, forKey: "battery_top_up_active")
            evaluatePowerManagement()
        }
    }

    @Published public var isTempAlertEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTempAlertEnabled, forKey: "battery_temp_alert_enabled")
        }
    }

    @Published public var isSmartAlertsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSmartAlertsEnabled, forKey: "battery_smart_alerts_enabled")
        }
    }

    // Hardware Tab Selection (0: Nguồn & Pin, 1: Sleep Guard, 2: Đóng băng CPU, 3: Hiệu chuẩn)
    @Published public var selectedHardwareTab: Int = 0

    // Sleep Guard Settings & State
    @Published public var isSleepGuardEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSleepGuardEnabled, forKey: "battery_sleep_guard_enabled")
        }
    }

    @Published public var sleepGuardTurnOffBluetooth: Bool = true {
        didSet {
            UserDefaults.standard.set(sleepGuardTurnOffBluetooth, forKey: "battery_sleep_guard_bt")
        }
    }

    @Published public var lastSleepReport: String = ""

    private var sleepDate: Date? = nil
    private var sleepBatteryLevel: Int = 0
    private var wasBluetoothTurnedOffBySleepGuard: Bool = false

    // Calibration State Machine
    public enum CalibrationState: String, CaseIterable {
        case idle = "idle"
        case discharging = "discharging"
        case charging = "charging"
        case resting = "resting"
        case completed = "completed"
    }

    @Published public var calibrationState: CalibrationState = .idle
    @Published public var calibrationMessage: String = ""
    private var restingTimer: Timer?

    // Auto-Scheduled Calibration
    @Published public var isAutoCalibrationEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAutoCalibrationEnabled, forKey: "battery_auto_calibration_enabled")
        }
    }

    @Published public var calibrationIntervalDays: Int = 30 {
        didSet {
            UserDefaults.standard.set(calibrationIntervalDays, forKey: "battery_calibration_interval_days")
        }
    }

    @Published public var lastCalibrationDate: Date? = nil {
        didSet {
            if let date = lastCalibrationDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
            }
        }
    }

    public var nextScheduledCalibrationDate: Date {
        let base = lastCalibrationDate ?? Date()
        return Calendar.current.date(byAdding: .day, value: calibrationIntervalDays, to: base) ?? Date()
    }

    public var daysRemainingUntilCalibration: Int {
        let now = Date()
        let next = nextScheduledCalibrationDate
        let diff = Calendar.current.dateComponents([.day], from: now, to: next).day ?? 0
        return max(0, diff)
    }

    public var tempAlertThreshold: Double = 38.0 // Warning at 38°C
    private var lastTempAlertDate: Date? = nil
    private var lastExtDisplayAlertDate: Date? = nil
    private var lastLowBatteryAlertLevel: Int? = nil
    private var hasAlertedBypassThisSession: Bool = false

    private var timer: Timer?

    private init() {
        // Load preferences
        if UserDefaults.standard.object(forKey: "battery_protection_enabled") != nil {
            self.isProtectionEnabled = UserDefaults.standard.bool(forKey: "battery_protection_enabled")
        } else {
            self.isProtectionEnabled = false
        }

        if UserDefaults.standard.object(forKey: "battery_temp_alert_enabled") != nil {
            self.isTempAlertEnabled = UserDefaults.standard.bool(forKey: "battery_temp_alert_enabled")
        } else {
            self.isTempAlertEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_smart_alerts_enabled") != nil {
            self.isSmartAlertsEnabled = UserDefaults.standard.bool(forKey: "battery_smart_alerts_enabled")
        } else {
            self.isSmartAlertsEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_enabled") != nil {
            self.isSleepGuardEnabled = UserDefaults.standard.bool(forKey: "battery_sleep_guard_enabled")
        } else {
            self.isSleepGuardEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_bt") != nil {
            self.sleepGuardTurnOffBluetooth = UserDefaults.standard.bool(forKey: "battery_sleep_guard_bt")
        } else {
            self.sleepGuardTurnOffBluetooth = true
        }

        self.lastSleepReport = UserDefaults.standard.string(forKey: "battery_last_sleep_report") ?? ""

        let savedLimit = UserDefaults.standard.integer(forKey: "battery_charge_limit")
        if savedLimit >= 50 && savedLimit <= 100 {
            self.chargeLimit = savedLimit
        } else {
            self.chargeLimit = 80
        }

        self.isTopUpActive = UserDefaults.standard.bool(forKey: "battery_top_up_active")

        if UserDefaults.standard.object(forKey: "battery_auto_calibration_enabled") != nil {
            self.isAutoCalibrationEnabled = UserDefaults.standard.bool(forKey: "battery_auto_calibration_enabled")
        } else {
            self.isAutoCalibrationEnabled = true
        }

        let savedInterval = UserDefaults.standard.integer(forKey: "battery_calibration_interval_days")
        if savedInterval >= 15 && savedInterval <= 120 {
            self.calibrationIntervalDays = savedInterval
        } else {
            self.calibrationIntervalDays = 30
        }

        let lastCalTimestamp = UserDefaults.standard.double(forKey: "battery_last_calibration_timestamp")
        if lastCalTimestamp > 0 {
            self.lastCalibrationDate = Date(timeIntervalSince1970: lastCalTimestamp)
        } else {
            let now = Date()
            self.lastCalibrationDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
        }

        // Setup Sleep Observers
        setupSleepObservers()

        // Initial check
        checkHelperStatus()
        refreshBatteryInfo()
        checkSMCBypassStatus()
        evaluatePowerManagement()

        // Start background polling timer
        startPolling()
    }

    deinit {
        timer?.invalidate()
        restingTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Sleep Guard Lifecycle

    private func setupSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        guard isSleepGuardEnabled else { return }
        self.sleepDate = Date()
        self.sleepBatteryLevel = self.currentLevel

        // Turn off Bluetooth if configured to prevent phantom Dark Wake drain
        if sleepGuardTurnOffBluetooth && BluetoothManager.shared.isAvailable && BluetoothManager.shared.isPowerOn {
            self.wasBluetoothTurnedOffBySleepGuard = true
            BluetoothManager.shared.isPowerOn = false
        }

        // Hard lock SMC to charge-off if at or above limit to prevent waking or sleep-charging overrides
        if isProtectionEnabled && currentLevel >= chargeLimit && isHelperInstalled {
            _ = shell("sudo -n /usr/local/bin/displaycontrol-power charge-off \(chargeLimit)")
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        guard isSleepGuardEnabled else { return }

        // Restore Bluetooth if previously turned off by Sleep Guard
        if wasBluetoothTurnedOffBySleepGuard && BluetoothManager.shared.isAvailable {
            BluetoothManager.shared.isPowerOn = true
            wasBluetoothTurnedOffBySleepGuard = false
        }

        // Re-enforce SMC Limit right upon wake
        evaluatePowerManagement()

        // Calculate sleep duration & battery delta
        if let sDate = sleepDate {
            let elapsed = Date().timeIntervalSince(sDate)
            let hours = Int(elapsed) / 3600
            let mins = (Int(elapsed) % 3600) / 60
            let delta = currentLevel - sleepBatteryLevel

            let drainText: String
            if delta >= 0 {
                drainText = "Hao pin: 0% (Hoàn hảo)"
            } else {
                drainText = "Hao pin: \(abs(delta))% (\(sleepBatteryLevel)% ➔ \(currentLevel)%)"
            }

            let report = "Gập máy \(hours)h\(mins)m • \(drainText) • SMC khóa an toàn"
            self.lastSleepReport = report
            UserDefaults.standard.set(report, forKey: "battery_last_sleep_report")

            if isSmartAlertsEnabled {
                sendNotification(
                    title: "Sleep Guard: Báo cáo khi mở máy",
                    body: "Máy đã nghỉ \(hours)h\(mins)m. \(drainText). Chế độ nguồn AC tiếp tục được bảo vệ!"
                )
            }
            self.sleepDate = nil
        }
    }

    // MARK: - Polling Timer

    public func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.refreshBatteryInfo()
                self.checkSMCBypassStatus()
                self.checkAutoCalibrationSchedule()
                self.evaluatePowerManagement()
            }
        }
    }

    // MARK: - IOKit Battery Status Query

    public func refreshBatteryInfo() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return
        }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        self.currentLevel = dict["CurrentCapacity"] as? Int ?? self.currentLevel
        self.maxCapacityPercent = dict["MaxCapacity"] as? Int ?? 100
        self.nominalCapacity = dict["NominalChargeCapacity"] as? Int ?? self.nominalCapacity
        self.designCapacity = dict["DesignCapacity"] as? Int ?? self.designCapacity
        self.cycleCount = dict["CycleCount"] as? Int ?? self.cycleCount
        self.isCharging = dict["IsCharging"] as? Bool ?? false
        self.isPluggedIn = dict["ExternalConnected"] as? Bool ?? false
        self.isFullyCharged = dict["FullyCharged"] as? Bool ?? false
        self.timeRemaining = dict["TimeRemaining"] as? Int ?? 0

        // If not physically plugged in, bypass cannot be active
        if !self.isPluggedIn {
            self.isBypassActive = false
        }

        if let rawTemp = dict["Temperature"] as? Double {
            self.temperature = rawTemp / 100.0
        } else if let rawTempInt = dict["Temperature"] as? Int {
            self.temperature = Double(rawTempInt) / 100.0
        }

        if let rawVolt = dict["Voltage"] as? Double {
            self.voltage = rawVolt / 1000.0
        } else if let rawVoltInt = dict["Voltage"] as? Int {
            self.voltage = Double(rawVoltInt) / 1000.0
        }

        if let rawAmp = dict["Amperage"] as? Int64 {
            // Signed 64-bit: negative = discharging, positive = charging, 0 = bypass
            self.amperage = Int(rawAmp)
        }

        // Live Wattage = Voltage (V) * abs(Amperage (A))
        self.wattage = (self.voltage * Double(abs(self.amperage))) / 1000.0

        // Parse Adapter details (only valid when plugged in)
        if self.isPluggedIn {
            if let adapter = dict["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
                self.adapterWatts = w
                self.adapterDescription = adapter["Description"] as? String ?? "USB-C PD"
                self.adapterSerial = adapter["SerialString"] as? String ?? ""
            } else if let adapterList = dict["AppleRawAdapterDetails"] as? [[String: Any]],
                      let first = adapterList.first,
                      let w = first["Watts"] as? Int, w > 0 {
                self.adapterWatts = w
                self.adapterDescription = first["Description"] as? String ?? "USB-C PD"
                self.adapterSerial = first["SerialString"] as? String ?? ""
            }
        } else {
            self.adapterWatts = 0
            self.adapterDescription = ""
            self.adapterSerial = ""
        }

        self.batterySerial = dict["Serial"] as? String ?? self.batterySerial
        self.gasGaugeChip = dict["DeviceName"] as? String ?? self.gasGaugeChip

        if self.designCapacity > 0 && self.nominalCapacity > 0 {
            let ratio = Double(self.nominalCapacity) / Double(self.designCapacity) * 100.0
            self.exactHealthPercent = ratio
            self.healthPercent = min(100, Int(round(ratio)))
        }

        self.lastUpdated = Date()
        checkTemperatureAlert()
        checkSmartSafetyAlerts()
    }

    // MARK: - Smart Safety & Anti-Wear Alerts

    private func checkSmartSafetyAlerts() {
        guard isSmartAlertsEnabled else { return }

        // 1. Alert: External display active but running on battery (not plugged in)
        let hasExtDisplay = DisplayManager.shared.monitors.contains(where: { !$0.isBuiltIn && $0.isConnected })
        if hasExtDisplay && !isPluggedIn {
            let now = Date()
            if lastExtDisplayAlertDate == nil || now.timeIntervalSince(lastExtDisplayAlertDate!) > 900 { // 15 mins
                lastExtDisplayAlertDate = now
                sendNotification(
                    title: "Đang dùng màn ngoài nhưng chưa cắm sạc!",
                    body: "Màn hình ngoài đang làm GPU xả pin rất nặng và nóng máy. Hãy cắm sạc để máy chạy điện trực tiếp và bảo vệ pin!"
                )
            }
        } else if isPluggedIn {
            lastExtDisplayAlertDate = nil
        }

        // 2. Alert: Low battery warning to prevent deep discharge (<20% and <10%)
        if !isPluggedIn {
            if currentLevel <= 10 {
                if lastLowBatteryAlertLevel != 10 {
                    lastLowBatteryAlertLevel = 10
                    sendNotification(
                        title: "🚨 KHẨN CẤP: Pin còn 10%!",
                        body: "Tuyệt đối không để máy dùng cạn đáy sập nguồn (gây hại cell pin vĩnh viễn). Hãy cắm sạc ngay!"
                    )
                }
            } else if currentLevel <= 20 {
                if lastLowBatteryAlertLevel != 20 {
                    lastLowBatteryAlertLevel = 20
                    sendNotification(
                        title: "Pin yếu (20%) - Hãy cắm sạc!",
                        body: "Để tránh hiện tượng tụt áp sâu (Deep Discharge) làm chai pin, hãy cắm sạc ngay bây giờ."
                    )
                }
            } else {
                lastLowBatteryAlertLevel = nil
            }
        } else {
            lastLowBatteryAlertLevel = nil
        }

        // 3. Informational Alert: Reached limit with AC Bypass active
        if isPluggedIn && isBypassActive && currentLevel >= chargeLimit {
            if !hasAlertedBypassThisSession {
                hasAlertedBypassThisSession = true
                sendNotification(
                    title: "Đã khóa \(chargeLimit)% - Chuyển sang nguồn AC trực tiếp",
                    body: "Pin đã được ngắt sạc an toàn. MacBook đang dùng điện trực tiếp từ củ sạc để chống chai pin tối đa!"
                )
            }
        } else if !isPluggedIn || currentLevel < (chargeLimit - 4) {
            hasAlertedBypassThisSession = false
        }
    }

    // MARK: - Temperature Safety Alerts

    private func checkTemperatureAlert() {
        guard isTempAlertEnabled && temperature >= tempAlertThreshold else { return }

        let now = Date()
        if let last = lastTempAlertDate, now.timeIntervalSince(last) < 600 {
            return // Wait at least 10 minutes between alerts
        }
        lastTempAlertDate = now

        let tempStr = String(format: "%.1f°C", temperature)
        sendNotification(
            title: "Cảnh báo nhiệt độ pin (\(tempStr))",
            body: "Nhiệt độ pin MacBook đã lên tới \(tempStr)! Hãy kê thoáng máy hoặc mở phần Giám sát năng lượng để đóng băng các tác vụ nặng."
        )
    }

    private func sendNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"Submarine\""
        DispatchQueue.global(qos: .utility).async {
            _ = shell("osascript -e '\(script)'")
        }
    }

    public func checkSMCBypassStatus() {
        if NativePowerUIClient.shared.isSupported {
            let enabled = NativePowerUIClient.shared.isCurrentlyEnabled()
            let limit = NativePowerUIClient.shared.currentLimit()
            if enabled && limit <= self.chargeLimit {
                self.isBypassActive = self.isPluggedIn
                return
            }
        }

        guard isHelperInstalled else { return }
        DispatchQueue.global(qos: .utility).async {
            let (out, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status 2>/dev/null")
            DispatchQueue.main.async {
                if code == 0 {
                    // Check if CHTE is 1 (bytes 01 00 00 00), BYPASS:1 or CH0B/BCLM active
                    let isBypassed = out.contains("BYPASS:1") ||
                                     out.contains("01 00 00 00") ||
                                     out.contains("1 (bytes 01 00 00 00)") ||
                                     out.contains("(bytes 02)")
                    self.isBypassActive = isBypassed && self.isPluggedIn
                } else {
                    self.isBypassActive = false
                }
            }
        }
    }

    // MARK: - Power & Limiter Evaluation

    public func evaluatePowerManagement() {
        guard isHelperInstalled else {
            statusMessage = "Cần cấp quyền để kích hoạt bảo vệ nguồn SMC"
            return
        }

        // 1. Calibration State handling
        if calibrationState != .idle {
            switch calibrationState {
            case .discharging:
                if currentLevel <= 20 {
                    calibrationState = .charging
                    calibrationMessage = tr("Bước 2/3: Sạc đầy 100% để cân bằng cell (Hiện tại: \(currentLevel)%)", "Step 2/3: Charging to 100% for cell balancing (Currently: \(currentLevel)%)")
                    setChargingInhibited(false)
                    sendNotification(
                        title: tr("Hiệu chuẩn pin: Đã đạt 20%", "Calibration: Reached 20%"),
                        body: isPluggedIn
                            ? tr("Đang sạc liên tục lên 100% để cân bằng điện áp các cell pin.", "Charging continuously to 100% to balance cell voltages.")
                            : tr("Hãy cắm sạc để HyperMac sạc cân bằng cell lên 100% và tự động khóa lại ở 80%.", "Please plug in charger to allow cell balancing up to 100%.")
                    )
                } else {
                    setChargingInhibited(true)
                    if isPluggedIn {
                        calibrationMessage = tr("Bước 1/3: Rút sạc dùng máy xuống 20% (Hiện tại: \(currentLevel)%)", "Step 1/3: Unplug and discharge to 20% (Currently: \(currentLevel)%)")
                    } else {
                        calibrationMessage = tr("Bước 1/3: Đang dùng pin xuống 20% (Hiện tại: \(currentLevel)%)", "Step 1/3: Discharging battery to 20% (Currently: \(currentLevel)%)")
                    }
                }
                return

            case .charging:
                if currentLevel >= 100 {
                    calibrationState = .resting
                    calibrationMessage = tr("Bước 3/3: Giữ 100% trong 15 phút để ổn định hóa chất cell...", "Step 3/3: Holding 100% for 15 min to stabilize chemistry...")
                    setChargingInhibited(false)
                    sendNotification(
                        title: tr("Hiệu chuẩn pin: Đạt 100%", "Calibration: Reached 100%"),
                        body: tr("Đang giữ 100% trong 15 phút để các cell pin cân bằng hoàn toàn.", "Holding 100% for 15 minutes to equalize all battery cells.")
                    )
                    restingTimer?.invalidate()
                    restingTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.completeCalibration()
                        }
                    }
                } else {
                    setChargingInhibited(false)
                    calibrationMessage = tr("Bước 2/3: Đang sạc lên 100% (Hiện tại: \(currentLevel)%)", "Step 2/3: Charging to 100% (Currently: \(currentLevel)%)")
                }
                return

            case .resting:
                return

            case .completed, .idle:
                break
            }
        }

        // 2. Normal power state
        if !isPluggedIn {
            self.isBypassActive = false
            statusMessage = tr("Đang dùng pin (\(currentLevel)%)", "On battery (\(currentLevel)%)")
            return
        }

        // Plugged in
        if isTopUpActive {
            setChargingInhibited(false)
            if currentLevel >= 100 {
                isTopUpActive = false
                statusMessage = tr("Đã sạc đầy 100%", "Fully charged 100%")
            } else {
                statusMessage = tr("Đang sạc đầy tạm thời (\(currentLevel)%)", "Temporary top-up (\(currentLevel)%)")
            }
            return
        }

        if isProtectionEnabled {
            if currentLevel >= chargeLimit {
                setChargingInhibited(true)
                statusMessage = tr("Nguồn AC trực tiếp (Đã khóa \(chargeLimit)% chống chai pin)", "Direct AC Power (Locked at \(chargeLimit)% to protect battery)")
            } else if currentLevel <= max(10, chargeLimit - 3) {
                setChargingInhibited(false)
                statusMessage = tr("Đang sạc bù lên \(chargeLimit)% (\(currentLevel)%)", "Recharging up to \(chargeLimit)% (\(currentLevel)%)")
            } else {
                if isBypassActive {
                    statusMessage = tr("Nguồn AC trực tiếp (\(currentLevel)%)", "Direct AC Power (\(currentLevel)%)")
                } else {
                    statusMessage = tr("Đang sạc (\(currentLevel)%)", "Charging (\(currentLevel)%)")
                }
            }
        } else {
            setChargingInhibited(false)
            statusMessage = isFullyCharged ? tr("Đã sạc đầy 100%", "Fully charged 100%") : tr("Đang sạc thường (\(currentLevel)%)", "Standard charging (\(currentLevel)%)")
        }
    }

    // MARK: - SMC Charging Inhibit Control

    public func setChargingInhibited(_ inhibit: Bool) {
        var nativeSuccess = false
        if NativePowerUIClient.shared.isSupported {
            if inhibit {
                nativeSuccess = NativePowerUIClient.shared.setLimit(chargeLimit)
            } else {
                nativeSuccess = NativePowerUIClient.shared.disable()
            }
            if nativeSuccess {
                self.isBypassActive = inhibit && self.isPluggedIn
            }
        }

        if isHelperInstalled {
            let cmd = inhibit
                ? "sudo -n /usr/local/bin/displaycontrol-power charge-off \(chargeLimit)"
                : "sudo -n /usr/local/bin/displaycontrol-power charge-on"
            DispatchQueue.global(qos: .utility).async {
                let (out, code) = shell(cmd)
                DispatchQueue.main.async {
                    if code == 0 {
                        self.isBypassActive = inhibit && self.isPluggedIn
                    } else if !nativeSuccess {
                        appLog("⚠️ setChargingInhibited(\(inhibit)) failed with code \(code): \(out)")
                    }
                }
            }
        }
    }

    // MARK: - Battery Calibration API & Auto-Scheduler

    public func checkAutoCalibrationSchedule() {
        guard isAutoCalibrationEnabled && calibrationState == .idle && isHelperInstalled else { return }
        guard let last = lastCalibrationDate else {
            lastCalibrationDate = Date()
            return
        }

        let now = Date()
        let daysPassed = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0

        if daysPassed >= calibrationIntervalDays {
            // Reached schedule!
            if currentLevel <= 25 && isPluggedIn {
                // Pin đã thấp sẵn và đang cắm sạc -> chuyển thẳng sang Bước 2 sạc cân bằng
                calibrationState = .charging
                calibrationMessage = tr("Bước 2/3: Đang sạc lên 100% để cân bằng cell (Hiện tại: \(currentLevel)%)", "Step 2/3: Charging to 100% for cell balancing (Currently: \(currentLevel)%)")
                setChargingInhibited(false)
                sendNotification(
                    title: tr("Bắt đầu hiệu chuẩn pin tự động", "Automatic Battery Calibration Started"),
                    body: tr("Pin đang ở mức \(currentLevel)%. HyperMac đang sạc lên 100% để cân bằng cell và sẽ tự động khóa lại ở 80%.", "Battery is at \(currentLevel)%. HyperMac is charging to 100% and will lock back to 80%.")
                )
            } else if calibrationState == .idle {
                startCalibration(isAutomatic: true)
            }
        }
    }

    public func startCalibration(isAutomatic: Bool = false) {
        guard isHelperInstalled else {
            statusMessage = tr("Cần cấp quyền SMC để hiệu chuẩn pin", "SMC Helper required for calibration")
            return
        }

        if currentLevel <= 22 {
            // Pin đã thấp sẵn -> bắt đầu sạc cân bằng ngay
            calibrationState = .charging
            calibrationMessage = tr("Bước 2/3: Đang sạc lên 100% để cân bằng cell (Hiện tại: \(currentLevel)%)", "Step 2/3: Charging to 100% for cell balancing (Currently: \(currentLevel)%)")
            setChargingInhibited(false)
            sendNotification(
                title: tr("Hiệu chuẩn pin: Bắt đầu sạc cân bằng cell", "Battery Calibration: Cell Balancing Started"),
                body: tr("Pin đang ở mức \(currentLevel)%. Đang nạp đầy 100% để cân bằng vi sai điện áp các cell.", "Battery is at \(currentLevel)%. Charging to 100% to equalize cell voltages.")
            )
            return
        }

        calibrationState = .discharging
        if isPluggedIn {
            calibrationMessage = tr("Bước 1/3: Rút sạc dùng máy xuống 20% (Hiện tại: \(currentLevel)%)", "Step 1/3: Unplug and discharge to 20% (Currently: \(currentLevel)%)")
        } else {
            calibrationMessage = tr("Bước 1/3: Đang dùng pin xuống 20% (Hiện tại: \(currentLevel)%)", "Step 1/3: Discharging battery to 20% (Currently: \(currentLevel)%)")
        }
        setChargingInhibited(true)

        let reason = isAutomatic ? tr("Tự động theo lịch \(calibrationIntervalDays) ngày", "Scheduled every \(calibrationIntervalDays) days") : tr("Thủ công", "Manual")
        sendNotification(
            title: tr("🔬 Bắt đầu hiệu chuẩn pin (\(reason))", "🔬 Battery Calibration Started (\(reason))"),
            body: isPluggedIn
                ? tr("Bước 1: Rút sạc dùng máy tự nhiên xuống mức 20%. Sau đó cắm sạc lại để HyperMac tự động làm phần còn lại.", "Step 1: Unplug and use battery down to 20%. Then plug in charger to complete.")
                : tr("Bước 1: Tiếp tục dùng pin xuống mức 20%. Sau đó cắm sạc lại để HyperMac tự động làm phần còn lại.", "Step 1: Continue battery use down to 20%. Then plug in charger to complete.")
        )
    }

    public func cancelCalibration() {
        calibrationState = .idle
        calibrationMessage = ""
        restingTimer?.invalidate()
        restingTimer = nil
        evaluatePowerManagement()
    }

    private func completeCalibration() {
        calibrationState = .completed
        self.lastCalibrationDate = Date()
        calibrationMessage = tr("🎉 Hiệu chuẩn hoàn tất! Lịch tiếp theo sau \(calibrationIntervalDays) ngày.", "🎉 Calibration complete! Next schedule in \(calibrationIntervalDays) days.")
        setChargingInhibited(true)
        sendNotification(
            title: tr("🎉 Hiệu chuẩn pin thành công!", "🎉 Battery Calibration Succeeded!"),
            body: tr("Dung lượng cell đã được cân bằng chính xác. Chế độ nguồn AC trực tiếp đã được tự động khóa lại ở \(chargeLimit)%.", "Cell capacities calibrated accurately. Direct AC power locked at \(chargeLimit)%.")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.calibrationState == .completed {
                self?.calibrationState = .idle
                self?.calibrationMessage = ""
                self?.evaluatePowerManagement()
            }
        }
    }

    // MARK: - Helper Installation Check & Prompt

    public func checkHelperStatus() {
        if NativePowerUIClient.shared.isSupported {
            self.isHelperInstalled = true
            if self.isProtectionEnabled {
                self.checkSMCBypassStatus()
                self.evaluatePowerManagement()
            }
            return
        }

        let exists = FileManager.default.fileExists(atPath: "/usr/local/bin/displaycontrol-power")
        if !exists {
            self.isHelperInstalled = false
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let (_, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status 2>/dev/null")
            DispatchQueue.main.async {
                self.isHelperInstalled = (code == 0)
                if self.isHelperInstalled && self.isProtectionEnabled {
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
            }
        }
    }

    public func installHelper(completion: ((Bool) -> Void)? = nil) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Find smc, helper and install script across bundle, working directory, and installed locations
            let searchDirs = [
                Bundle.main.resourcePath,
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path,
                "/Applications/HyperMac.app/Contents/Resources",
                FileManager.default.currentDirectoryPath + "/Resources"
            ].compactMap { $0 }

            var smcSrc: String? = Bundle.main.path(forResource: "smc", ofType: nil)
            var helperSrc: String? = Bundle.main.path(forResource: "displaycontrol-power", ofType: nil)
            var installScript: String? = Bundle.main.path(forResource: "install-helper", ofType: "sh")

            for dir in searchDirs {
                if smcSrc == nil {
                    let path = (dir as NSString).appendingPathComponent("smc")
                    if FileManager.default.fileExists(atPath: path) { smcSrc = path }
                }
                if helperSrc == nil {
                    let path = (dir as NSString).appendingPathComponent("displaycontrol-power")
                    if FileManager.default.fileExists(atPath: path) { helperSrc = path }
                }
                if installScript == nil {
                    let path = (dir as NSString).appendingPathComponent("install-helper.sh")
                    if FileManager.default.fileExists(atPath: path) { installScript = path }
                }
            }

            guard let sSMC = smcSrc, let sHelper = helperSrc, let sInstall = installScript else {
                appLog("❌ installHelper: missing resource paths (smc: \(smcSrc ?? "nil"), helper: \(helperSrc ?? "nil"), script: \(installScript ?? "nil"))")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let appleScriptCmd = """
            do shell script "/bin/bash '\(sInstall)' '\(sSMC)' '\(sHelper)'" with administrator privileges
            """

            var errorDict: NSDictionary?
            if let scriptObj = NSAppleScript(source: appleScriptCmd) {
                _ = scriptObj.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    appLog("⚠️ installHelper AppleScript error: \(err)")
                }
            }

            // Verify installation
            let (_, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status 2>/dev/null")
            let success = (code == 0)

            DispatchQueue.main.async {
                self.isInstallingHelper = false
                self.isHelperInstalled = success
                if success {
                    self.isProtectionEnabled = true
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
                completion?(success)
            }
        }
    }
}
