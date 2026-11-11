import Foundation
import IOKit
import IOKit.ps
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
        guard cls.instancesRespond(to: selInit) else { return }

        // Use alloc + initWithClientName: cleanly without double-init
        let selAlloc = NSSelectorFromString("alloc")
        guard cls.responds(to: selAlloc) else { return }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject
        let allocFn = unsafeBitCast(cls.method(for: selAlloc), to: AllocFn.self)
        let uninit = allocFn(cls, selAlloc)

        typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        let initFn = unsafeBitCast(cls.instanceMethod(for: selInit), to: InitFn.self)
        let client = initFn(uninit, selInit, "HyperMac" as NSString) as? NSObject
        self.clientInstance = client

        let selSupported = NSSelectorFromString("isMCLSupported")
        if let client = client, client.responds(to: selSupported) {
            typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
            let fn = unsafeBitCast(client.method(for: selSupported), to: BoolFn.self)
            self.isSupported = fn(client, selSupported)
        }
    }

    public func setLimit(_ limit: Int) -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        // Apple Native PowerUI only supports limits: 80, 85, 90, 95, 100.
        // If limit < 80 (e.g. 70%), PowerUI will reject with error code 4.
        guard limit >= 80 else { return false }

        let selSet = NSSelectorFromString("setMCLLimit:error:")
        guard client.responds(to: selSet) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutableRawPointer?) -> Bool
        // Pass NULL for error pointer to avoid any Swift ARC double-free issues
        let ok = unsafeBitCast(client.method(for: selSet), to: SetFn.self)(client, selSet, UInt8(min(max(limit, 80), 100)), nil)

        // Ensure MCL is also explicitly enabled in powerd (writes byte 1 = 0x01 in SMC CHLT)
        let selEnable = NSSelectorFromString("enableMCL:")
        if client.responds(to: selEnable) {
            typealias EnableFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
            _ = unsafeBitCast(client.method(for: selEnable), to: EnableFn.self)(client, selEnable, nil)
        }

        if ok {
            appLog("🔋 NativePowerUIClient: setMCLLimit(\(limit)) + enableMCL succeeded")
        } else {
            appLog("⚠️ NativePowerUIClient: setMCLLimit(\(limit)) rejected by system")
        }
        return ok
    }

    public func disable() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selDisable = NSSelectorFromString("disableMCL:")
        guard client.responds(to: selDisable) else { return false }
        typealias DisableFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
        // Pass NULL for error pointer
        let ok = unsafeBitCast(client.method(for: selDisable), to: DisableFn.self)(client, selDisable, nil)
        if ok {
            appLog("🔋 NativePowerUIClient: disableMCL succeeded (charging restored)")
        } else {
            appLog("⚠️ NativePowerUIClient: disableMCL failed")
        }
        return ok
    }

    public func isCurrentlyEnabled() -> Bool {
        guard isSupported, let client = clientInstance else { return false }
        let selEnabled = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard client.responds(to: selEnabled) else { return false }
        typealias BoolErrFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> UInt64
        // Pass NULL for error pointer
        let res = unsafeBitCast(client.method(for: selEnabled), to: BoolErrFn.self)(client, selEnabled, nil)
        return res != 0
    }

    public func currentLimit() -> Int {
        guard isSupported, let client = clientInstance else { return 100 }
        let selGet = NSSelectorFromString("getMCLLimitWithError:")
        guard client.responds(to: selGet) else { return 100 }
        typealias UcharErrFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> UInt8
        // Pass NULL for error pointer
        let limit = unsafeBitCast(client.method(for: selGet), to: UcharErrFn.self)(client, selGet, nil)
        return Int(limit)
    }
}

// MARK: - Battery Manager (Hardware Care & Longevity)

@MainActor
public class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    // MARK: - Published State
    @Published public var hasBattery: Bool = true
    @Published public var currentLevel: Int = 100
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
    @Published public var helperVersion: Int = 0
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
            updateAppNapProtection()
            if !isProtectionEnabled {
                self.isBypassActive = false
                setChargingInhibited(false, forceImmediate: true)
            }
            evaluatePowerManagement()
            syncPollingTimer()
        }
    }

    @Published public var chargeLimit: Int = 80 {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "battery_charge_limit")
            lastAppliedLimit = 0 // Force immediate SMC re-apply on limit change
            evaluatePowerManagement()
        }
    }

    @Published public var isTopUpActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isTopUpActive, forKey: "battery_top_up_active")
            updateAppNapProtection()
            lastAppliedInhibitState = nil
            evaluatePowerManagement()
            syncPollingTimer()
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
    private var timerInterval: TimeInterval = 0
    private var isPopoverVisible: Bool = false
    private let smcClient = AppleSMCClient()
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var appNapActivityToken: NSObjectProtocol?
    private var lastAppliedInhibitState: Bool? = nil
    private var lastAppliedLimit: Int = 0
    private var lastSMCWriteDate: Date = .distantPast
    private var consecutiveChargeSpikes: Int = 0

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

        // Setup Sleep & Real-Time IOPowerSources Observers
        setupSleepObservers()
        setupPowerSourceNotifications()
        updateAppNapProtection()

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
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let token = appNapActivityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Real-Time Hardware Power Notifications & App Nap Prevention

    private func setupPowerSourceNotifications() {
        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                let bm = BatteryManager.shared
                bm.refreshBatteryInfo()
                bm.checkSMCBypassStatus()
                bm.evaluatePowerManagement()
                bm.updateAppNapProtection()
                bm.syncPollingTimer()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            self.powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func updateAppNapProtection() {
        // Chỉ giữ App Nap token khi đang cắm sạc VÀ đang nạp lên ngưỡng hoặc hiệu chuẩn.
        // Khi đang dùng pin (!isPluggedIn) hoặc đã khóa bypass xong (isBypassActive),
        // nhả ngay token để macOS gộp timer và tiết kiệm năng lượng.
        let needsActiveMonitoring = isPluggedIn &&
            ((isProtectionEnabled && !isBypassActive) || isTopUpActive || calibrationState != .idle)
        if needsActiveMonitoring {
            if appNapActivityToken == nil {
                appNapActivityToken = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "HyperMac Active Charging Limiter"
                )
            }
        } else if let token = appNapActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            appNapActivityToken = nil
        }
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
        // 1. Always enforce battery charge limit before sleep (even if Sleep Guard BT feature is off)
        if isProtectionEnabled && !isTopUpActive && calibrationState == .idle {
            if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
                _ = NativePowerUIClient.shared.setLimit(chargeLimit)
            }
            if isHelperInstalled {
                if currentLevel >= chargeLimit {
                    _ = shell(PrivilegedHelper.sudo("charge-off \(chargeLimit)"))
                } else {
                    _ = shell(PrivilegedHelper.sudo("charge-on \(chargeLimit)"))
                }
            }
        }

        // 2. Sleep Guard Bluetooth & drain tracking
        guard isSleepGuardEnabled else { return }
        self.sleepDate = Date()
        self.sleepBatteryLevel = self.currentLevel

        // Turn off Bluetooth if configured to prevent phantom Dark Wake drain
        if sleepGuardTurnOffBluetooth && BluetoothManager.shared.isAvailable && BluetoothManager.shared.isPowerOn {
            self.wasBluetoothTurnedOffBySleepGuard = true
            BluetoothManager.shared.isPowerOn = false
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        // 1. Always refresh battery state and re-enforce SMC limit immediately upon wake
        lastAppliedInhibitState = nil
        refreshBatteryInfo()
        checkSMCBypassStatus()
        evaluatePowerManagement()

        // 2. Sleep Guard Bluetooth restoration & report
        guard isSleepGuardEnabled else { return }

        // Restore Bluetooth if previously turned off by Sleep Guard
        if wasBluetoothTurnedOffBySleepGuard && BluetoothManager.shared.isAvailable {
            BluetoothManager.shared.isPowerOn = true
            wasBluetoothTurnedOffBySleepGuard = false
        }

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

    // MARK: - Polling Timer (Dynamic & Energy-Aware)

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            refreshBatteryInfo()
            checkSMCBypassStatus()
            evaluatePowerManagement()
            updateAppNapProtection()
        }
        syncPollingTimer()
    }

    public func startPolling() {
        syncPollingTimer()
    }

    private func syncPollingTimer() {
        let desiredInterval: TimeInterval
        if !hasBattery {
            desiredInterval = 0
        } else if isPopoverVisible {
            desiredInterval = 3.5
        } else if isPluggedIn && (isProtectionEnabled || isTopUpActive || calibrationState != .idle) {
            // Khi popover đóng và đang cắm sạc, chỉ kiểm tra in-process mỗi 20s (0 tiến trình con);
            // sự kiện cắm/rút/đổi % đã được IOPSNotification báo tức thì.
            desiredInterval = 20.0
        } else {
            // Đang dùng pin hoặc không bật bảo vệ khi đóng popover: 0 timer wakeup, dựa hoàn toàn vào IOPSNotification + didWake.
            desiredInterval = 0
        }

        if desiredInterval <= 0 {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            return
        }

        guard timer == nil || timerInterval != desiredInterval else { return }
        timer?.invalidate()
        timerInterval = desiredInterval
        let t = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshBatteryInfo()
                self.checkSMCBypassStatus()
                self.checkAutoCalibrationSchedule()
                self.evaluatePowerManagement()
                self.updateAppNapProtection()
                self.syncPollingTimer()
            }
        }
        t.tolerance = desiredInterval >= 15.0 ? 4.0 : 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func setIfChanged<T: Equatable>(_ target: inout T, _ newValue: T) {
        if target != newValue {
            target = newValue
        }
    }

    // MARK: - IOKit Battery Status Query

    public func refreshBatteryInfo() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            // Desktop Macs (Mac mini, Mac Studio Max/Ultra, iMac, Mac Pro) do not have an internal battery
            setIfChanged(&self.hasBattery, false)
            setIfChanged(&self.isPluggedIn, true)
            setIfChanged(&self.isCharging, false)
            setIfChanged(&self.isFullyCharged, true)
            setIfChanged(&self.currentLevel, 100)
            setIfChanged(&self.statusMessage, tr("Nguồn AC trực tiếp (Máy bàn Mac)", "Direct AC Power (Desktop Mac)"))
            syncPollingTimer()
            updateAppNapProtection()
            return
        }
        defer { IOObjectRelease(service) }
        setIfChanged(&self.hasBattery, true)

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        setIfChanged(&self.currentLevel, dict["CurrentCapacity"] as? Int ?? self.currentLevel)
        setIfChanged(&self.maxCapacityPercent, dict["MaxCapacity"] as? Int ?? 100)
        setIfChanged(&self.nominalCapacity, dict["NominalChargeCapacity"] as? Int ?? self.nominalCapacity)
        setIfChanged(&self.designCapacity, dict["DesignCapacity"] as? Int ?? self.designCapacity)
        setIfChanged(&self.cycleCount, dict["CycleCount"] as? Int ?? self.cycleCount)
        let rawCharging = dict["IsCharging"] as? Bool ?? false
        setIfChanged(&self.isPluggedIn, dict["ExternalConnected"] as? Bool ?? false)
        setIfChanged(&self.isFullyCharged, dict["FullyCharged"] as? Bool ?? false)
        setIfChanged(&self.timeRemaining, dict["TimeRemaining"] as? Int ?? 0)

        // If not physically plugged in or protection is disabled, bypass cannot be active
        if !self.isPluggedIn || !self.isProtectionEnabled {
            setIfChanged(&self.isBypassActive, false)
        }

        if let rawTemp = dict["Temperature"] as? Double {
            let t = rawTemp / 100.0
            if abs(self.temperature - t) >= 0.05 { self.temperature = t }
        } else if let rawTempInt = dict["Temperature"] as? Int {
            let t = Double(rawTempInt) / 100.0
            if abs(self.temperature - t) >= 0.05 { self.temperature = t }
        }

        if let rawVolt = dict["Voltage"] as? Double {
            let v = rawVolt / 1000.0
            if abs(self.voltage - v) >= 0.01 { self.voltage = v }
        } else if let rawVoltInt = dict["Voltage"] as? Int {
            let v = Double(rawVoltInt) / 1000.0
            if abs(self.voltage - v) >= 0.01 { self.voltage = v }
        }

        if let rawAmp = dict["Amperage"] as? Int64 {
            // Signed 64-bit: negative = discharging, positive = charging, 0 = bypass
            setIfChanged(&self.amperage, Int(rawAmp))
        }

        // Live Wattage = Voltage (V) * abs(Amperage (A))
        let newWattage = (self.voltage * Double(abs(self.amperage))) / 1000.0
        if abs(self.wattage - newWattage) >= 0.05 {
            self.wattage = newWattage
        }

        // Responsive charging detection: even if macOS IsCharging flag is delayed, positive current means charging
        let nextCharging = rawCharging || (self.isPluggedIn && self.amperage > 50)
        setIfChanged(&self.isCharging, nextCharging)

        // Parse Adapter details (only valid when plugged in)
        if self.isPluggedIn {
            if let adapter = dict["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
                setIfChanged(&self.adapterWatts, w)
                setIfChanged(&self.adapterDescription, adapter["Description"] as? String ?? "USB-C PD")
                setIfChanged(&self.adapterSerial, adapter["SerialString"] as? String ?? "")
            } else if let adapterList = dict["AppleRawAdapterDetails"] as? [[String: Any]],
                      let first = adapterList.first,
                      let w = first["Watts"] as? Int, w > 0 {
                setIfChanged(&self.adapterWatts, w)
                setIfChanged(&self.adapterDescription, first["Description"] as? String ?? "USB-C PD")
                setIfChanged(&self.adapterSerial, first["SerialString"] as? String ?? "")
            }
        } else {
            setIfChanged(&self.adapterWatts, 0)
            setIfChanged(&self.adapterDescription, "")
            setIfChanged(&self.adapterSerial, "")
        }

        setIfChanged(&self.batterySerial, dict["Serial"] as? String ?? self.batterySerial)
        setIfChanged(&self.gasGaugeChip, dict["DeviceName"] as? String ?? self.gasGaugeChip)

        if self.designCapacity > 0 && self.nominalCapacity > 0 {
            let ratio = Double(self.nominalCapacity) / Double(self.designCapacity) * 100.0
            if abs(self.exactHealthPercent - ratio) >= 0.01 {
                self.exactHealthPercent = ratio
            }
            setIfChanged(&self.healthPercent, min(100, Int(round(ratio))))
        }

        if isPopoverVisible {
            self.lastUpdated = Date()
        }
        checkTemperatureAlert()
        checkSmartSafetyAlerts()
    }

    // MARK: - Smart Safety & Anti-Wear Alerts

    private func checkSmartSafetyAlerts() {
        guard isSmartAlertsEnabled && hasBattery else { return }

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

    /// Đọc trạng thái khóa sạc SMC trực tiếp in-process qua IOKit AppleSMC (`0ms`, 0 tiến trình con, 0 sudo).
    /// Trả `nil` nếu thiết bị không có khóa SMC nào (khi đó fallback sang PowerUI MCL).
    private func readHardwareBypassInProcess() -> Bool? {
        var foundKey = false
        var bypassed = false

        if let chte = smcClient.readKeyBytes("CHTE"), !chte.isEmpty {
            foundKey = true
            if chte[0] == 1 { bypassed = true }
        }
        if let ch0b = smcClient.readKeyBytes("CH0B"), !ch0b.isEmpty {
            foundKey = true
            if ch0b[0] == 2 { bypassed = true }
        }
        if let bff0 = smcClient.readKeyBytes("bfF0"), !bff0.isEmpty {
            foundKey = true
            if bff0[0] == 1 || bff0[0] == 2 { bypassed = true }
        }
        if let bclm = smcClient.readKeyBytes("BCLM"), !bclm.isEmpty {
            foundKey = true
            if bclm[0] > 0 && bclm[0] < 100 { bypassed = true }
        }

        return foundKey ? bypassed : nil
    }

    public func checkSMCBypassStatus() {
        // If protection is disabled by user, bypass is NEVER active
        guard isProtectionEnabled else {
            setIfChanged(&self.isBypassActive, false)
            return
        }

        // 1. Đọc trực tiếp từ IOKit AppleSMC trong tiến trình (0 tiến trình con, không cần sudo!)
        if let smcBypassed = readHardwareBypassInProcess() {
            // Nếu đang ở/vượt ngưỡng mà dòng sạc >120mA liên tục, phần cứng đã bị reset (cắm lại MagSafe/USB-C PD)
            if currentLevel >= chargeLimit && amperage > 120 {
                consecutiveChargeSpikes += 1
            } else {
                consecutiveChargeSpikes = 0
            }
            let activelyChargingPastLimit = isPluggedIn && (currentLevel >= chargeLimit) && (isCharging || consecutiveChargeSpikes >= 2)
            setIfChanged(&self.isBypassActive, smcBypassed && isPluggedIn && !activelyChargingPastLimit)
            return
        }

        // 2. Fallback when SMC register is unavailable (Native PowerUI only)
        if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
            let enabled = NativePowerUIClient.shared.isCurrentlyEnabled()
            let limit = NativePowerUIClient.shared.currentLimit()
            if enabled && limit <= self.chargeLimit && self.currentLevel >= self.chargeLimit && !self.isCharging {
                setIfChanged(&self.isBypassActive, self.isPluggedIn)
                return
            }
        }
        setIfChanged(&self.isBypassActive, false)
    }

    // MARK: - Power & Limiter Evaluation

    public func evaluatePowerManagement() {
        guard hasBattery else {
            setIfChanged(&self.isBypassActive, false)
            setIfChanged(&statusMessage, tr("Nguồn AC trực tiếp (Máy bàn Mac)", "Direct AC Power (Desktop Mac)"))
            return
        }
        guard isHelperInstalled || (NativePowerUIClient.shared.isSupported && chargeLimit >= 80) else {
            setIfChanged(&statusMessage, tr("Cần cấp quyền để kích hoạt bảo vệ nguồn SMC", "Permission needed for SMC power protection"))
            return
        }

        // 1. Calibration State handling
        if calibrationState != .idle {
            switch calibrationState {
            case .discharging:
                if currentLevel <= 20 {
                    calibrationState = .charging
                    calibrationMessage = tr("Bước 2/3: Sạc đầy 100% để cân bằng cell (Hiện tại: \(currentLevel)%)", "Step 2/3: Charging to 100% for cell balancing (Currently: \(currentLevel)%)")
                    setChargingInhibited(false, forceImmediate: true)
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
            setIfChanged(&self.isBypassActive, false)
            // Keep firmware ceiling armed even while on battery if protection is enabled,
            // so plugging in while asleep won't overshoot the limit
            if isProtectionEnabled && !isTopUpActive && NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
                if !NativePowerUIClient.shared.isCurrentlyEnabled() || NativePowerUIClient.shared.currentLimit() != chargeLimit {
                    _ = NativePowerUIClient.shared.setLimit(chargeLimit)
                }
            }
            setIfChanged(&statusMessage, tr("Đang dùng pin (\(currentLevel)%)", "On battery (\(currentLevel)%)"))
            return
        }

        // Plugged in
        if isTopUpActive {
            setChargingInhibited(false)
            if currentLevel >= 100 {
                isTopUpActive = false
                setIfChanged(&statusMessage, tr("Đã sạc đầy 100%", "Fully charged 100%"))
            } else {
                setIfChanged(&statusMessage, tr("Đang sạc đầy tạm thời (\(currentLevel)%)", "Temporary top-up (\(currentLevel)%)"))
            }
            return
        }

        if isProtectionEnabled {
            if currentLevel >= chargeLimit {
                // Chỉ gọi sudo ghi lại SMC khi khóa phần cứng chưa active hoặc đang có dòng sạc vào pin
                let needsUrgentLock = !isBypassActive || isCharging || amperage > 120
                setChargingInhibited(true, forceImmediate: needsUrgentLock)
                setIfChanged(&statusMessage, tr("Nguồn AC trực tiếp (Đã khóa \(chargeLimit)% chống chai pin)", "Direct AC Power (Locked at \(chargeLimit)% to protect battery)"))
            } else if currentLevel <= max(10, chargeLimit - 3) {
                setChargingInhibited(false)
                setIfChanged(&statusMessage, tr("Đang sạc bù lên \(chargeLimit)% (\(currentLevel)%)", "Recharging up to \(chargeLimit)% (\(currentLevel)%)"))
            } else {
                // Hysteresis band (e.g. 78% - 79% when limit is 80%)
                if isBypassActive {
                    setChargingInhibited(true)
                    setIfChanged(&statusMessage, tr("Nguồn AC trực tiếp (\(currentLevel)%)", "Direct AC Power (\(currentLevel)%)"))
                } else {
                    setChargingInhibited(false)
                    setIfChanged(&statusMessage, tr("Đang sạc lên \(chargeLimit)% (\(currentLevel)%)", "Charging to \(chargeLimit)% (\(currentLevel)%)"))
                }
            }
        } else {
            setChargingInhibited(false)
            setIfChanged(&statusMessage, isFullyCharged ? tr("Đã sạc đầy 100%", "Fully charged 100%") : tr("Đang sạc thường (\(currentLevel)%)", "Standard charging (\(currentLevel)%)"))
        }
    }

    // MARK: - SMC Charging Inhibit Control

    public func setChargingInhibited(_ inhibit: Bool, forceImmediate: Bool = false) {
        let now = Date()
        let cooldownElapsed = now.timeIntervalSince(lastSMCWriteDate) >= 10.0
        let stateOrLimitChanged = (lastAppliedInhibitState != inhibit) || (lastAppliedLimit != chargeLimit)
        let shouldWriteSMC = stateOrLimitChanged || (forceImmediate && cooldownElapsed)

        if !inhibit {
            setIfChanged(&self.isBypassActive, false)
            // Determine whether we are recharging up to `chargeLimit` (keep ceiling armed!)
            // vs. completely unlocking to 100% (Protection OFF, Top-Up 100%, or Calibration charging)
            let keepCeilingArmed = isProtectionEnabled && !isTopUpActive && (calibrationState == .idle)

            if keepCeilingArmed {
                // Keep firmware ceiling (CHLT / PowerUI) armed at `chargeLimit` so Mac stops at `chargeLimit` even during Sleep!
                if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
                    if stateOrLimitChanged || !NativePowerUIClient.shared.isCurrentlyEnabled() || NativePowerUIClient.shared.currentLimit() != chargeLimit {
                        _ = NativePowerUIClient.shared.setLimit(chargeLimit)
                    }
                }
            } else {
                // Full 100% unlock: disable native macOS PowerUI MCL
                if NativePowerUIClient.shared.isSupported {
                    if stateOrLimitChanged || NativePowerUIClient.shared.isCurrentlyEnabled() {
                        _ = NativePowerUIClient.shared.disable()
                    }
                }
            }

            // Chỉ chạy sudo helper khi vừa chuyển trạng thái / vừa mở khóa hoặc khi đọc SMC thấy công tắc vẫn đang đóng
            let hardwareStillInhibited = (readHardwareBypassInProcess() == true)
            if isHelperInstalled && (shouldWriteSMC || (hardwareStillInhibited && cooldownElapsed)) {
                lastAppliedInhibitState = false
                lastAppliedLimit = chargeLimit
                lastSMCWriteDate = now
                let targetCeiling = keepCeilingArmed ? chargeLimit : 100
                DispatchQueue.global(qos: .utility).async {
                    let (_, _) = shell(PrivilegedHelper.sudo("charge-on \(targetCeiling)"))
                    DispatchQueue.main.async {
                        self.setIfChanged(&self.isBypassActive, false)
                        self.refreshBatteryInfo()
                    }
                }
            }
            return
        }

        // Inhibit = true (Lock charging at specified limit & switch to Direct AC Power)
        // Layer 1: Arm Native PowerUI / CHLT firmware ceiling (for macOS 15+ / sleep persistence)
        var nativeSuccess = false
        if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
            if !NativePowerUIClient.shared.isCurrentlyEnabled() || NativePowerUIClient.shared.currentLimit() != chargeLimit {
                nativeSuccess = NativePowerUIClient.shared.setLimit(chargeLimit)
            } else {
                nativeSuccess = true
            }
        }

        // Layer 2: ALWAYS enforce SMC hardware cut-off switches (CHTE / CH0B / bfF0 / BCLM) via root helper
        // when state/limit changes or in-process read detects bypass is missing / still charging (0 background spam when already locked!).
        if isHelperInstalled {
            let needsLockWrite = shouldWriteSMC || (!isBypassActive && cooldownElapsed) || ((isCharging || amperage > 120) && cooldownElapsed)
            if needsLockWrite {
                lastAppliedInhibitState = true
                lastAppliedLimit = chargeLimit
                lastSMCWriteDate = now
                let limitToLock = chargeLimit
                let cmd = PrivilegedHelper.sudo("charge-off \(limitToLock)")
                DispatchQueue.global(qos: .utility).async {
                    let (out, code) = shell(cmd)
                    DispatchQueue.main.async {
                        if code == 0 {
                            self.setIfChanged(&self.isBypassActive, self.isPluggedIn)
                            self.updateAppNapProtection()
                        } else if !nativeSuccess {
                            appLog("⚠️ setChargingInhibited(true) failed with code \(code): \(out)")
                        }
                    }
                }
            }
        } else if nativeSuccess {
            setIfChanged(&self.isBypassActive, self.isPluggedIn)
        }
    }

    /// Gọi đồng bộ khi thoát ứng dụng (`applicationWillTerminate`) để nhả công tắc cứng `CHTE`/`CH0B`,
    /// tránh việc Mac bị kẹt ngắt sạc khi HyperMac đã tắt, trong khi vẫn giữ trần `CHLT` nếu đang bật bảo vệ.
    public func restoreOnTerminateSync() {
        guard hasBattery else { return }
        let keepCeiling = isProtectionEnabled && !isTopUpActive && (calibrationState == .idle)
        if keepCeiling {
            if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
                _ = NativePowerUIClient.shared.setLimit(chargeLimit)
            }
            if isHelperInstalled {
                _ = shell(PrivilegedHelper.sudo("charge-on \(chargeLimit) 2>/dev/null"))
            }
        } else {
            if NativePowerUIClient.shared.isSupported {
                _ = NativePowerUIClient.shared.disable()
            }
            if isHelperInstalled {
                _ = shell(PrivilegedHelper.sudo("charge-on 100 2>/dev/null"))
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

    public func checkHelperStatus(completion: ((Bool) -> Void)? = nil) {
        let exists = FileManager.default.fileExists(atPath: PrivilegedHelper.powerPath)
        guard exists else {
            let hasLegacy = FileManager.default.fileExists(atPath: PrivilegedHelper.legacyPowerPath)
            self.isHelperInstalled = false
            self.helperVersion = hasLegacy ? 2 : 0
            if self.isProtectionEnabled {
                self.checkSMCBypassStatus()
                self.evaluatePowerManagement()
            }
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let (out, code) = shell(PrivilegedHelper.sudo("version 2>&1"))
            var ver = 0
            if code == 0, let r = out.range(of: "HELPER_VERSION:") {
                ver = Int(out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber })) ?? 0
            }
            // Không còn dùng helper cũ (<= v2 ở /usr/local/bin với sudoers mở cho mọi user);
            // người dùng cài lại 1 lần lên v3 trong /Library/PrivilegedHelperTools, bộ cài tự gỡ bản cũ.
            let isRealReady = (ver >= PrivilegedHelper.requiredVersion)
            DispatchQueue.main.async {
                self.helperVersion = ver
                self.isHelperInstalled = isRealReady
                if self.isProtectionEnabled {
                    self.lastAppliedInhibitState = nil
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
                completion?(isRealReady)
            }
        }
    }

    public func installHelper(completion: ((Bool) -> Void)? = nil) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Chỉ lấy tệp nguồn từ app bundle (hoặc /Applications/HyperMac.app), tuyệt đối không lấy từ thư mục làm việc hiện tại.
            let searchDirs = [
                Bundle.main.resourcePath,
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path,
                "/Applications/HyperMac.app/Contents/Resources"
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

            // Kiểm tra tên user chặt chẽ trước khi ghi rule sudoers
            let user = NSUserName()
            guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
                  !user.hasPrefix("-"), user != ".", user != "..", user != "ALL", user != "root"
            else {
                appLog("❌ installHelper: unsafe user name")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            // Stage bản sao sạch vào thư mục riêng tư (0700) trong /private/tmp để tránh lỗi TCC khi app chạy từ ~/Downloads hoặc ~/Documents
            let fm = FileManager.default
            let stageURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("hypermac-helper-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: stageURL) }

            let stagedSMC = stageURL.appendingPathComponent("smc").path
            let stagedHelper = stageURL.appendingPathComponent("displaycontrol-power").path
            let stagedInstall = stageURL.appendingPathComponent("install-helper.sh").path

            do {
                try fm.createDirectory(at: stageURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try fm.copyItem(atPath: sSMC, toPath: stagedSMC)
                try fm.copyItem(atPath: sHelper, toPath: stagedHelper)
                try fm.copyItem(atPath: sInstall, toPath: stagedInstall)
            } catch {
                appLog("❌ installHelper: failed staging resources: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let stagedPaths = [stagedInstall, stagedSMC, stagedHelper]
            guard !stagedPaths.contains(where: { $0.contains("'") || $0.contains("\\") || $0.contains("\"") }) else {
                appLog("❌ installHelper: unsafe staged path")
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let appleScriptCmd = """
            do shell script "/bin/bash '\(stagedInstall)' '\(stagedSMC)' '\(stagedHelper)' '\(user)'" with administrator privileges
            """

            var errorDict: NSDictionary?
            if let scriptObj = NSAppleScript(source: appleScriptCmd) {
                _ = scriptObj.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    appLog("⚠️ installHelper AppleScript error: \(err)")
                }
            }

            // Verify installation with deep probe
            let (out, code) = shell(PrivilegedHelper.sudo("version 2>&1"))
            var ver = 0
            if code == 0, let r = out.range(of: "HELPER_VERSION:") {
                ver = Int(out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber })) ?? 0
            }
            let success = (code == 0 && ver >= PrivilegedHelper.requiredVersion)

            DispatchQueue.main.async {
                self.isInstallingHelper = false
                self.helperVersion = ver
                self.isHelperInstalled = success
                if success {
                    self.isProtectionEnabled = true
                    self.checkSMCBypassStatus()
                    self.evaluatePowerManagement()
                }
                FanManager.shared.checkHelper()
                completion?(success)
            }
        }
    }
}
