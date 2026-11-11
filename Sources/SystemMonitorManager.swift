// SPDX-License-Identifier: GPL-3.0-only
// HyperMac — Copyright (C) 2026 Nguyễn Khắc Đại
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
// See the LICENSE file in the repository root for the full text.

import Foundation
import AppKit
import IOKit
import Darwin

/// Theo dõi % CPU, % RAM và % GPU (nếu thiết bị hỗ trợ) bằng Mach & IOKit thuần (không gọi shell/Process).
/// Chỉ chạy polling timer khi ít nhất một tùy chọn hiển thị Menu Bar đang bật để giữ 0% idle CPU.
@MainActor
public final class SystemMonitorManager: ObservableObject {
    public static let shared = SystemMonitorManager()

    private enum Keys {
        static let showCPURAM = "show_menubar_cpu_ram"
        static let showGPU = "show_menubar_gpu"
    }

    /// Cache tĩnh port và kích thước trang kernel một lần duy nhất:
    /// Mỗi lần gọi `mach_host_self()` tạo thêm +1 Mach send right nếu không cache sẽ rò rỉ port.
    private static let machHostPort: mach_port_t = mach_host_self()
    private static let hostPageSizeBytes: UInt64 = {
        var size: vm_size_t = 0
        if host_page_size(machHostPort, &size) == KERN_SUCCESS, size > 0 {
            return UInt64(size)
        }
        return UInt64(vm_kernel_page_size)
    }()

    @Published public var showCPURAMMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showCPURAMMenuBar, forKey: Keys.showCPURAM)
            syncPollingState()
        }
    }

    @Published public var showGPUMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showGPUMenuBar, forKey: Keys.showGPU)
            syncPollingState()
        }
    }

    @Published public private(set) var cpuUsagePercent: Double = 0.0
    @Published public private(set) var ramUsagePercent: Double = 0.0
    @Published public private(set) var gpuUsagePercent: Double = 0.0
    @Published public private(set) var hasGPU: Bool = false

    public var onStatsUpdate: (() -> Void)?

    private struct CoreTicks {
        let user: UInt32
        let sys: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private var prevCoreTicks: [CoreTicks]?
    private var pollTimer: Timer?
    private var initialDeltaWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        self.showCPURAMMenuBar = UserDefaults.standard.bool(forKey: Keys.showCPURAM)
        self.showGPUMenuBar = UserDefaults.standard.bool(forKey: Keys.showGPU)

        if let initialGPU = Self.readGPUUtilization() {
            self.hasGPU = true
            self.gpuUsagePercent = initialGPU
        } else {
            self.hasGPU = false
        }

        // Đặt lại baseline CPU khi máy vừa thức dậy từ sleep để tránh delta rác
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }

        syncPollingState()
    }

    deinit {
        pollTimer?.invalidate()
        initialDeltaWork?.cancel()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Chuỗi tóm tắt hiển thị trên Menu Bar theo các tùy chọn đang bật.
    public func formattedMenuBarSummary() -> String? {
        var parts: [String] = []
        if showCPURAMMenuBar {
            let cpu = Int(cpuUsagePercent.rounded())
            let ram = Int(ramUsagePercent.rounded())
            parts.append("CPU \(cpu)% · RAM \(ram)%")
        }
        if showGPUMenuBar && hasGPU {
            let gpu = Int(gpuUsagePercent.rounded())
            parts.append("GPU \(gpu)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Lấy mẫu tức thì một lần cho giao diện preview hoặc sau khi bật toggle.
    public func refreshNow() {
        sampleMetrics()
    }

    private func handleSystemWake() {
        prevCoreTicks = nil
        if showCPURAMMenuBar || showGPUMenuBar {
            syncPollingState()
        }
    }

    private func syncPollingState() {
        initialDeltaWork?.cancel()
        initialDeltaWork = nil

        let shouldPoll = showCPURAMMenuBar || showGPUMenuBar
        guard shouldPoll else {
            pollTimer?.invalidate()
            pollTimer = nil
            prevCoreTicks = nil
            onStatsUpdate?()
            return
        }

        let needsInitialCPUDelta = showCPURAMMenuBar && (prevCoreTicks == nil)
        sampleMetrics()

        if needsInitialCPUDelta {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.showCPURAMMenuBar else { return }
                    self.sampleMetrics()
                }
            }
            initialDeltaWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        if pollTimer == nil {
            let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sampleMetrics()
                }
            }
            timer.tolerance = 0.4
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private func sampleMetrics() {
        if showCPURAMMenuBar {
            if let cores = Self.readCoreTicks() {
                if let prev = prevCoreTicks, prev.count == cores.count {
                    self.cpuUsagePercent = Self.computeCPUDelta(from: prev, to: cores)
                }
                prevCoreTicks = cores
            }
            self.ramUsagePercent = Self.readRAMUsagePercent()
        }

        if showGPUMenuBar || !hasGPU {
            if let gpu = Self.readGPUUtilization() {
                self.hasGPU = true
                self.gpuUsagePercent = gpu
            }
        }

        onStatsUpdate?()
    }

    // MARK: - Low-Level Mach & IOKit Samplers

    private static func readCoreTicks() -> [CoreTicks]? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            machHostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }

        defer {
            let byteSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), byteSize)
        }

        guard numCPUs > 0 else { return nil }

        var resultCores: [CoreTicks] = []
        resultCores.reserveCapacity(Int(numCPUs))
        info.withMemoryRebound(to: processor_cpu_load_info_data_t.self, capacity: Int(numCPUs)) { loads in
            for i in 0..<Int(numCPUs) {
                let t = loads[i].cpu_ticks
                resultCores.append(CoreTicks(
                    user: UInt32(bitPattern: Int32(t.0)),
                    sys: UInt32(bitPattern: Int32(t.1)),
                    idle: UInt32(bitPattern: Int32(t.2)),
                    nice: UInt32(bitPattern: Int32(t.3))
                ))
            }
        }
        return resultCores
    }

    /// Trừ wrapping (`&-`) theo từng core trên `UInt32` để chống gai 100% CPU khi uptime dài vượt 2^32 ticks.
    private static func computeCPUDelta(from prev: [CoreTicks], to curr: [CoreTicks]) -> Double {
        var totalActive: UInt64 = 0
        var totalTicks: UInt64 = 0

        for i in 0..<curr.count {
            let userDiff = UInt64(curr[i].user &- prev[i].user)
            let sysDiff = UInt64(curr[i].sys &- prev[i].sys)
            let idleDiff = UInt64(curr[i].idle &- prev[i].idle)
            let niceDiff = UInt64(curr[i].nice &- prev[i].nice)

            let active = userDiff &+ sysDiff &+ niceDiff
            totalActive &+= active
            totalTicks &+= active &+ idleDiff
        }

        guard totalTicks > 0 else { return 0.0 }
        return min(max(Double(totalActive) / Double(totalTicks) * 100.0, 0.0), 100.0)
    }

    /// Tính % RAM theo công thức "Memory Used" thực tế của macOS Activity Monitor:
    /// (App Memory [internal - purgeable] + Wired + Compressed) / PhysicalMemory.
    private static func readRAMUsagePercent() -> Double {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0, hostPageSizeBytes > 0 else { return 0.0 }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(machHostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0.0 }

        let appPages: UInt64 = stats.internal_page_count >= stats.purgeable_count
            ? UInt64(stats.internal_page_count - stats.purgeable_count)
            : 0
        let usedPages = appPages
            &+ UInt64(stats.wire_count)
            &+ UInt64(stats.compressor_page_count)
        let usedBytes = usedPages.multipliedReportingOverflow(by: hostPageSizeBytes)
        guard !usedBytes.overflow else { return 100.0 }

        return min(max((Double(usedBytes.partialValue) / Double(totalBytes)) * 100.0, 0.0), 100.0)
    }

    private static func readGPUUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let gpuKeys = ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %", "GPU Activity"]
        var bestUtil: Double?

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let agc = dict["AGCInfo"] as? [String: Any],
               (agc["poweredOffByAGC"] as? NSNumber)?.intValue == 1 {
                continue
            }

            guard let perf = dict["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            for key in gpuKeys {
                if let value = (perf[key] as? NSNumber)?.doubleValue {
                    let clamped = min(max(value, 0.0), 100.0)
                    bestUtil = max(bestUtil ?? 0.0, clamped)
                    break
                }
            }
        }
        return bestUtil
    }
}
