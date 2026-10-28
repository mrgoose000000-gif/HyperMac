import Foundation
import IOKit
import Darwin

// MARK: - Models

public struct DiskSpeedInfo: Identifiable, Equatable {
    public let bsdName: String
    public let displayName: String
    public let readMBps: Double
    public let writeMBps: Double

    public var id: String { bsdName }
    public var isActive: Bool { readMBps >= 0.05 || writeMBps >= 0.05 }
    public var totalMBps: Double { readMBps + writeMBps }
}

struct DiskSpeedSnapshot {
    var disks: [DiskSpeedInfo] = []
    var networkReadMBps: Double = 0
    var networkWriteMBps: Double = 0
    var networkLabel: String? = nil
    var topProcessName: String? = nil
    var topProcessReadMBps: Double = 0
    var topProcessWriteMBps: Double = 0

    var totalReadMBps: Double { disks.reduce(0) { $0 + $1.readMBps } }
    var totalWriteMBps: Double { disks.reduce(0) { $0 + $1.writeMBps } }
}

// MARK: - Sampler (chạy hoàn toàn trên background queue)

/// Đọc bộ đếm IOKit của từng ổ vật lý, bộ đếm interface mạng (cho NAS/SMB)
/// và bộ đếm I/O theo tiến trình; sau đó quy ra MB/s theo delta thời gian.
final class DiskSpeedSampler {
    private var lastTime: TimeInterval = 0
    private var prevDisks: [String: (r: UInt64, w: UInt64)] = [:]
    private var prevNetwork: [String: (r: UInt64, w: UInt64)] = [:]
    private var prevProcess: [Int32: (r: UInt64, w: UInt64)] = [:]
    private var routeCache: [String: (iface: String, at: TimeInterval)] = [:]
    private var cachedNetworkHosts: [String] = []
    private var networkHostsCheckedAt: TimeInterval = 0

    func sample() -> DiskSpeedSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTime == 0 ? 1.0 : max(0.25, now - lastTime)
        lastTime = now

        var snapshot = DiskSpeedSnapshot()

        // ── 1. Ổ vật lý ──
        let (counters, volumeNames) = Self.readDiskCounters()
        for (bsd, current) in counters {
            let previous = prevDisks[bsd] ?? current
            let read = Self.mbps(current.r, previous.r, dt)
            let write = Self.mbps(current.w, previous.w, dt)
            snapshot.disks.append(DiskSpeedInfo(
                bsdName: bsd,
                displayName: volumeNames[bsd] ?? bsd,
                readMBps: read,
                writeMBps: write
            ))
        }
        prevDisks = counters
        snapshot.disks.sort { $0.bsdName < $1.bsdName }

        // ── 2. Ổ mạng (NAS/SMB/AFP) → đo interface đang gánh đường tới host ──
        if now - networkHostsCheckedAt > 10 {
            cachedNetworkHosts = Self.networkVolumeHosts()
            networkHostsCheckedAt = now
        }
        if let host = cachedNetworkHosts.first {
            let iface = interfaceName(forHost: host, now: now)
            let netCounters = Self.readInterfaceCounters()
            if let iface, let current = netCounters[iface] {
                let previous = prevNetwork[iface] ?? current
                snapshot.networkReadMBps = Self.mbps(current.r, previous.r, dt)
                snapshot.networkWriteMBps = Self.mbps(current.w, previous.w, dt)
                snapshot.networkLabel = "LAN \(iface)"
            } else {
                // Không resolve được interface: cộng các interface đang hoạt động.
                var totalR: UInt64 = 0
                var totalW: UInt64 = 0
                for (name, current) in netCounters where Self.isPhysicalInterface(name) {
                    let previous = prevNetwork[name] ?? current
                    totalR &+= current.r &- previous.r
                    totalW &+= current.w &- previous.w
                }
                snapshot.networkReadMBps = Double(totalR) / 1_048_576.0 / dt
                snapshot.networkWriteMBps = Double(totalW) / 1_048_576.0 / dt
                snapshot.networkLabel = "LAN"
            }
            prevNetwork = netCounters
        } else {
            prevNetwork = [:]
            networkHostsCheckedAt = 0
        }

        // ── 3. Tiến trình đang ghi/đọc nhiều nhất ──
        let procCounters = Self.readProcessCounters()
        var bestPid: Int32? = nil
        var bestWrite: Double = 0
        var bestRead: Double = 0
        for (pid, current) in procCounters {
            guard let previous = prevProcess[pid] else { continue }
            let write = Self.mbps(current.w, previous.w, dt)
            let read = Self.mbps(current.r, previous.r, dt)
            if max(write, read) > max(bestWrite, bestRead) {
                bestPid = pid
                bestWrite = write
                bestRead = read
            }
        }
        prevProcess = procCounters

        if let pid = bestPid, let name = Self.processName(pid) {
            let peak = max(bestWrite, bestRead)
            let throughput = max(
                snapshot.totalReadMBps, snapshot.totalWriteMBps,
                snapshot.networkReadMBps, snapshot.networkWriteMBps
            )
            // Chỉ gắn tên tiến trình khi nó thực sự chiếm phần lớn lưu lượng.
            // I/O nền (Spotlight, Shortcuts…) hoặc cache ghi thường tạo delta nhỏ,
            // gán bừa sẽ hiển thị sai tiến trình đang chép file.
            if peak >= 3.0, throughput > 0, peak >= throughput * 0.5 {
                snapshot.topProcessName = name
                snapshot.topProcessWriteMBps = bestWrite
                snapshot.topProcessReadMBps = bestRead
            }
        }

        return snapshot
    }

    // MARK: - Disk counters (IOKit)

    private static func readDiskCounters() -> ([String: (r: UInt64, w: UInt64)], [String: String]) {
        var counters: [String: (r: UInt64, w: UInt64)] = [:]
        var names = volumeNamesByPhysicalDisk()

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == KERN_SUCCESS else {
            return (counters, names)
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let media = IOIteratorNext(iterator)
            if media == 0 { break }
            defer { IOObjectRelease(media) }

            guard let whole = IORegistryEntryCreateCFProperty(media, "Whole" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                  whole.boolValue,
                  let bsd = IORegistryEntryCreateCFProperty(media, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            else { continue }

            // Chỉ lấy cha TRỰC TIẾP là IOBlockStorageDriver. Các "disk" tổng hợp
            // của APFS (disk1, disk3…) có cha là AppleAPFSContainerScheme cũng có
            // Statistics riêng → nếu không lọc sẽ cộng trùng gấp đôi tốc độ.
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            guard classOf(parent) == "IOBlockStorageDriver" else {
                IOObjectRelease(parent)
                continue
            }

            guard let stats = IORegistryEntryCreateCFProperty(parent, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value,
                  let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value
            else {
                IOObjectRelease(parent)
                continue
            }

            counters[bsd] = (read, write)
            if names[bsd] == nil {
                names[bsd] = productName(ofDriver: parent).map(Self.prettyDiskName) ?? bsd.uppercased()
            }
            IOObjectRelease(parent)
        }

        return (counters, names)
    }

    private static func classOf(_ entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &buffer) == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    private static func productName(ofDriver driver: io_registry_entry_t) -> String? {
        var device: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &device) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(device) }
        guard let characteristics = IORegistryEntryCreateCFProperty(device, "Device Characteristics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return nil }
        return characteristics["Product Name"] as? String
    }

    private static func prettyDiskName(_ product: String) -> String {
        if product.uppercased().contains("APPLE SSD") { return "SSD nội bộ" }
        return product
    }

    /// Ghép BSD name của Ổ VẬT LÝ với tên volume đang mount.
    /// APFS lồng nhiều tầng (disk4 → container disk5 → volume disk5s1) nên phải
    /// đi ngược lên cha để tìm đúng ổ vật lý. Trên 1 ổ có thể có nhiều volume
    /// (Data, Preboot, VM…) nên chọn volume lớn nhất, ưu tiên volume gốc "/".
    private static func volumeNamesByPhysicalDisk() -> [String: String] {
        var result: [String: String] = [:]
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return result }

        struct Candidate {
            let name: String
            let priority: Int
            let size: Int64
        }
        var best: [String: Candidate] = [:]

        for index in 0..<Int(count) {
            let fs = mounts[index]
            let source = withUnsafePointer(to: fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard source.hasPrefix("/dev/") else { continue }
            let device = String(source.dropFirst(5))

            let mountPoint = withUnsafePointer(to: fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard let media = mediaEntry(forBSDName: device), let base = physicalBase(of: media) else { continue }
            IOObjectRelease(media)

            let isRoot = (mountPoint == "/")
            let rawName = URL(fileURLWithPath: mountPoint).lastPathComponent
            let name = (isRoot || rawName.isEmpty) ? "Macintosh HD" : rawName
            let size = Int64(fs.f_blocks) * Int64(fs.f_bsize)

            let candidate = Candidate(name: name, priority: isRoot ? 2 : 1, size: size)
            if let current = best[base] {
                if candidate.priority > current.priority ||
                    (candidate.priority == current.priority && candidate.size > current.size) {
                    best[base] = candidate
                }
            } else {
                best[base] = candidate
            }
        }

        for (base, candidate) in best {
            result[base] = candidate.name
        }
        return result
    }

    private static func mediaEntry(forBSDName name: String) -> io_registry_entry_t? {
        let match = IOBSDNameMatching(kIOMainPortDefault, 0, name)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
        return service == 0 ? nil : service
    }

    /// Đi ngược cây IORegistry tới IOMedia có cha là IOBlockStorageDriver.
    private static func physicalBase(of media: io_registry_entry_t) -> String? {
        var current = media
        IOObjectRetain(current)
        var depth = 0

        while depth < 12 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                IOObjectRelease(current)
                return nil
            }

            if classOf(parent) == "IOBlockStorageDriver" {
                let bsd = IORegistryEntryCreateCFProperty(current, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                IOObjectRelease(parent)
                IOObjectRelease(current)
                return bsd
            }

            IOObjectRelease(current)
            current = parent
            depth += 1
        }

        IOObjectRelease(current)
        return nil
    }

    // MARK: - Network

    private static func networkVolumeHosts() -> [String] {
        var hosts: [String] = []
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return hosts }

        for index in 0..<Int(count) {
            let fs = mounts[index]
            let source = withUnsafePointer(to: fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard !source.hasPrefix("/dev/"), !source.hasPrefix("/") else { continue }
            if let host = hostFromMountSource(source), !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }

    /// "//user@192.168.1.10/Share" → "192.168.1.10"; "nas.local:/volume" → "nas.local"
    private static func hostFromMountSource(_ source: String) -> String? {
        if source.hasPrefix("//") {
            var rest = String(source.dropFirst(2))
            if let at = rest.lastIndex(of: "@") {
                rest = String(rest[rest.index(after: at)...])
            }
            if let slash = rest.firstIndex(of: "/") {
                rest = String(rest[..<slash])
            }
            return rest.isEmpty ? nil : rest
        }
        if let colon = source.firstIndex(of: ":") {
            let host = String(source[..<colon])
            return host.isEmpty ? nil : host
        }
        return nil
    }

    private func interfaceName(forHost host: String, now: TimeInterval) -> String? {
        if let cached = routeCache[host], now - cached.at < 60 { return cached.iface }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            for line in output.split(separator: "\n") where line.contains("interface:") {
                let iface = line.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                if !iface.isEmpty {
                    routeCache[host] = (iface, now)
                    return iface
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func isPhysicalInterface(_ name: String) -> Bool {
        guard name.hasPrefix("en") || name.hasPrefix("ppp") else { return false }
        return true
    }

    /// Bộ đếm byte của từng interface qua sysctl NET_RT_IFLIST2 (số 64-bit).
    private static func readInterfaceCounters() -> [String: (r: UInt64, w: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (r: UInt64, w: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let pointer = base.advanced(by: offset)
                let header = pointer.assumingMemoryBound(to: if_msghdr.self).pointee
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let header2 = pointer.assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(header2.ifm_index), &nameBuffer) != nil {
                        result[String(cString: nameBuffer)] = (header2.ifm_data.ifi_ibytes, header2.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    // MARK: - Per-process I/O

    private static func readProcessCounters() -> [Int32: (r: UInt64, w: UInt64)] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [:] }

        var result: [Int32: (r: UInt64, w: UInt64)] = [:]
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
                }
            }
            if status == 0 {
                result[pid] = (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
            }
        }
        return result
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Helpers

    /// Chênh lệch byte → MB/s, có xử lý bộ đếm bị reset/wrap.
    private static func mbps(_ current: UInt64, _ previous: UInt64, _ seconds: TimeInterval) -> Double {
        guard current >= previous else { return 0 }
        return Double(current - previous) / 1_048_576.0 / seconds
    }
}

// MARK: - Manager (UI-facing)

@MainActor
public final class DiskSpeedManager: ObservableObject {
    public static let shared = DiskSpeedManager()

    @Published public private(set) var disks: [DiskSpeedInfo] = []
    @Published public private(set) var totalReadMBps: Double = 0
    @Published public private(set) var totalWriteMBps: Double = 0
    @Published public private(set) var networkReadMBps: Double = 0
    @Published public private(set) var networkWriteMBps: Double = 0
    @Published public private(set) var networkLabel: String? = nil
    @Published public private(set) var topProcessName: String? = nil
    @Published public private(set) var topProcessReadMBps: Double = 0
    @Published public private(set) var topProcessWriteMBps: Double = 0

    private let queue = DispatchQueue(label: "com.hypermac.diskspeed", qos: .utility)
    private let sampler = DiskSpeedSampler()
    private var timer: Timer?
    private var isSampling = false
    private let debugLogging = ProcessInfo.processInfo.environment["HYPERMAC_DISKSPEED_DEBUG"] == "1"

    private init() {
        start()
    }

    private func start() {
        timer?.invalidate()
        let pollTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer
    }

    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.sampler.sample()
            DispatchQueue.main.async {
                self.apply(snapshot)
                self.isSampling = false
            }
        }
    }

    private func apply(_ snapshot: DiskSpeedSnapshot) {
        disks = snapshot.disks
        totalReadMBps = snapshot.totalReadMBps
        totalWriteMBps = snapshot.totalWriteMBps
        networkReadMBps = snapshot.networkReadMBps
        networkWriteMBps = snapshot.networkWriteMBps
        networkLabel = snapshot.networkLabel
        topProcessName = snapshot.topProcessName
        topProcessReadMBps = snapshot.topProcessReadMBps
        topProcessWriteMBps = snapshot.topProcessWriteMBps

        if debugLogging {
            let diskText = snapshot.disks
                .map { "\($0.bsdName)/\($0.displayName) r\(String(format: "%.1f", $0.readMBps)) w\(String(format: "%.1f", $0.writeMBps))" }
                .joined(separator: ", ")
            appLog("💾 DiskSpeed: total r\(String(format: "%.2f", snapshot.totalReadMBps)) w\(String(format: "%.2f", snapshot.totalWriteMBps)) MB/s | net \(snapshot.networkLabel ?? "-") r\(String(format: "%.2f", snapshot.networkReadMBps)) w\(String(format: "%.2f", snapshot.networkWriteMBps)) | proc \(snapshot.topProcessName ?? "-") | \(diskText)")
        }
    }
}
