// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import IOKit

// MARK: - DDC/CI Protocol (pure logic, unit-tested)

/// Đóng gói / giải mã gói tin DDC/CI (VESA MCCS) dùng qua I2C.
/// Tách riêng khỏi IOKit để kiểm thử được bằng unit test.
enum DDCPacket {
    /// Địa chỉ I2C 7-bit của khối DDC/CI trên màn hình.
    static let chipAddress: UInt32 = 0x37
    /// Sub-address của host (byte đầu tiên trong frame DDC/CI).
    static let hostSubAddress: UInt32 = 0x51
    /// Địa chỉ ghi của màn hình (0x37 << 1), tham gia vào checksum.
    static let displayWriteAddress: UInt8 = 0x6E
    /// Địa chỉ I2C của EEPROM chứa EDID.
    static let edidAddress: UInt32 = 0x50

    /// Mã VCP độ sáng (Luminance).
    static let luminanceCode: UInt8 = 0x10

    static func checksum(_ bytes: [UInt8], seed: UInt8) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Gói "Set VCP Feature": [len|0x80, 0x03, code, hi, lo, checksum].
    static func setVCP(code: UInt8, value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        return body + [checksum(body, seed: displayWriteAddress ^ UInt8(hostSubAddress))]
    }

    /// Gói "Get VCP Feature": [len|0x80, 0x01, code, checksum].
    static func getVCPRequest(code: UInt8) -> [UInt8] {
        let body: [UInt8] = [0x82, 0x01, code]
        return body + [checksum(body, seed: displayWriteAddress ^ UInt8(hostSubAddress))]
    }

    /// Giải mã phản hồi "Get VCP Feature Reply".
    /// Bố cục: [src 0x6E, len 0x88, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, checksum].
    static func parseGetVCPReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 11 else { return nil }
        guard reply[1] == 0x88, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        // Không bắt buộc checksum: nhiều màn hình phổ thông trả checksum sai dù dữ liệu đúng.
        // Cấu trúc frame (len/opcode/result/code) + kiểm tra max > 0 đã đủ lọc rác.
        let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maxValue > 0, current <= maxValue else { return nil }
        return (current, maxValue)
    }

    /// Định danh màn hình đọc từ 16 byte đầu của EDID.
    struct EDIDIdentity: Equatable {
        let vendor: UInt32
        let product: UInt32
        let serial: UInt32
    }

    static func parseEDID(_ edid: [UInt8]) -> EDIDIdentity? {
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard edid.count >= 16, Array(edid[0..<8]) == header else { return nil }
        // Mã nhà sản xuất: big-endian (giống giá trị CGDisplayVendorNumber trả về).
        let vendor = UInt32(edid[8]) << 8 | UInt32(edid[9])
        // Mã sản phẩm và serial: little-endian.
        let product = UInt32(edid[10]) | UInt32(edid[11]) << 8
        let serial = UInt32(edid[12]) | UInt32(edid[13]) << 8 | UInt32(edid[14]) << 16 | UInt32(edid[15]) << 24
        return EDIDIdentity(vendor: vendor, product: product, serial: serial)
    }

    /// Ghép danh sách màn hình CoreGraphics với các service DDC theo EDID.
    /// Ưu tiên khớp cả vendor + product + serial; nếu serial = 0 hoặc trùng (2 màn giống hệt) thì khớp
    /// theo vendor + product và chia lần lượt theo thứ tự. Mỗi service chỉ được dùng một lần.
    static func match(
        displays: [(id: CGDirectDisplayID, identity: EDIDIdentity)],
        services: [EDIDIdentity?]
    ) -> [CGDirectDisplayID: Int] {
        var result: [CGDirectDisplayID: Int] = [:]
        var used = Set<Int>()

        // Lượt 1: khớp chính xác (serial khác 0).
        for display in displays where display.identity.serial != 0 {
            if let idx = services.indices.first(where: { !used.contains($0) && services[$0] == display.identity }) {
                result[display.id] = idx
                used.insert(idx)
            }
        }
        // Lượt 2: khớp vendor + product.
        for display in displays where result[display.id] == nil {
            if let idx = services.indices.first(where: {
                guard !used.contains($0), let s = services[$0] else { return false }
                return s.vendor == display.identity.vendor && s.product == display.identity.product
            }) {
                result[display.id] = idx
                used.insert(idx)
            }
        }
        // Lượt 3: còn đúng 1 màn và 1 service chưa ghép (EDID không đọc được) thì ghép luôn.
        let leftDisplays = displays.filter { result[$0.id] == nil }
        let leftServices = services.indices.filter { !used.contains($0) }
        if leftDisplays.count == 1, leftServices.count == 1 {
            result[leftDisplays[0].id] = leftServices[0]
        }
        return result
    }
}

// MARK: - Private IOAVService symbols (Apple Silicon)

private typealias IOAVServiceCreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias IOAVServiceI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
private typealias IOAVServiceCopyEDIDFn = @convention(c) (CFTypeRef, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn

private struct IOAVServiceSymbols {
    let create: IOAVServiceCreateWithServiceFn
    let read: IOAVServiceI2CFn
    let write: IOAVServiceI2CFn
    let copyEDID: IOAVServiceCopyEDIDFn?

    /// Tra symbol lúc chạy: nếu macOS đổi API thì DDC tự tắt, app vẫn chạy bằng gamma.
    static let shared: IOAVServiceSymbols? = {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym(_ name: String) -> UnsafeMutableRawPointer? {
            if let handle, let p = dlsym(handle, name) { return p }
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
        }
        guard let c = sym("IOAVServiceCreateWithService"),
              let r = sym("IOAVServiceReadI2C"),
              let w = sym("IOAVServiceWriteI2C") else {
            appLog("⚠️ DDC: IOAVService symbols unavailable — falling back to gamma.")
            return nil
        }
        return IOAVServiceSymbols(
            create: unsafeBitCast(c, to: IOAVServiceCreateWithServiceFn.self),
            read: unsafeBitCast(r, to: IOAVServiceI2CFn.self),
            write: unsafeBitCast(w, to: IOAVServiceI2CFn.self),
            copyEDID: sym("IOAVServiceCopyEDID").map { unsafeBitCast($0, to: IOAVServiceCopyEDIDFn.self) }
        )
    }()
}

// MARK: - DDC Service

/// Điều khiển độ sáng phần cứng màn ngoài qua DDC/CI (IOAVService) trên Apple Silicon.
/// Mọi thao tác I2C chạy trên một hàng đợi nối tiếp riêng (I2C chậm ~50ms/lệnh, không được chặn main thread).
/// Lệnh ghi được gộp: kéo slider nhanh chỉ gửi giá trị mới nhất.
final class DDCService: @unchecked Sendable {
    static let shared = DDCService()

    struct Target: Sendable {
        let id: CGDirectDisplayID
        let vendor: UInt32
        let product: UInt32
        let serial: UInt32
    }

    private let queue = DispatchQueue(label: "hypermac.ddc", qos: .userInitiated)
    private let lock = NSLock()
    /// displayID -> IOAVService (chỉ truy cập trên `queue`).
    private var services: [CGDirectDisplayID: CFTypeRef] = [:]
    /// displayID -> giá trị max VCP độ sáng đã đọc được.
    private var maxLuminance: [CGDirectDisplayID: UInt16] = [:]
    /// Giá trị đang chờ ghi (gộp lệnh), bảo vệ bởi `lock`.
    private var pendingWrites: [CGDirectDisplayID: Double] = [:]
    private var scheduledWrites: Set<CGDirectDisplayID> = []

    private init() {}

    var isAvailable: Bool { IOAVServiceSymbols.shared != nil }

    /// Ghép lại service cho danh sách màn ngoài rồi đọc độ sáng hiện tại.
    /// `completion` chạy trên main thread: displayID -> độ sáng (0...1), hoặc nil nếu màn không hỗ trợ DDC.
    func probe(_ targets: [Target], completion: @escaping @Sendable ([CGDirectDisplayID: Double?]) -> Void) {
        queue.async { [self] in
            var results: [CGDirectDisplayID: Double?] = [:]
            guard let symbols = IOAVServiceSymbols.shared, !targets.isEmpty else {
                for t in targets { results[t.id] = .some(nil) }
                DispatchQueue.main.async { completion(results) }
                return
            }

            let found = Self.externalServices(symbols)
            let identities = found.map { readEDIDIdentity($0, symbols) }
            let mapping = DDCPacket.match(
                displays: targets.map { ($0.id, DDCPacket.EDIDIdentity(vendor: $0.vendor, product: $0.product, serial: $0.serial)) },
                services: identities
            )

            services = [:]
            maxLuminance = [:]
            for target in targets {
                guard let idx = mapping[target.id] else {
                    results[target.id] = .some(nil)
                    continue
                }
                let service = found[idx]
                if let reading = readLuminance(service, symbols, attempts: 3) {
                    services[target.id] = service
                    maxLuminance[target.id] = reading.max
                    results[target.id] = Double(reading.current) / Double(reading.max)
                    appLog("✅ DDC: display \(target.id) OK (luminance \(reading.current)/\(reading.max))")
                } else {
                    results[target.id] = .some(nil)
                    appLog("ℹ️ DDC: display \(target.id) did not answer — using gamma.")
                }
            }
            DispatchQueue.main.async { completion(results) }
        }
    }

    /// Ghi độ sáng (0...1). Gọi liên tục khi kéo slider vẫn an toàn: chỉ giá trị cuối cùng được gửi.
    /// `onFailure` chạy trên main thread nếu màn ngừng phản hồi DDC.
    func setBrightness(_ value: Double, for id: CGDirectDisplayID, onFailure: @escaping @Sendable () -> Void) {
        lock.lock()
        pendingWrites[id] = max(0, min(1, value))
        let needsSchedule = !scheduledWrites.contains(id)
        if needsSchedule { scheduledWrites.insert(id) }
        lock.unlock()
        guard needsSchedule else { return }

        queue.async { [self] in
            lock.lock()
            let latest = pendingWrites.removeValue(forKey: id)
            scheduledWrites.remove(id)
            lock.unlock()

            guard let latest, let symbols = IOAVServiceSymbols.shared,
                  let service = services[id], let maxValue = maxLuminance[id] else { return }

            let raw = UInt16((latest * Double(maxValue)).rounded())
            if !writeVCP(service, symbols, code: DDCPacket.luminanceCode, value: raw) {
                services.removeValue(forKey: id)
                appLog("⚠️ DDC: write failed for display \(id) — switching to gamma.")
                DispatchQueue.main.async { onFailure() }
            }
            // Màn hình cần nghỉ giữa các lệnh DDC liên tiếp.
            usleep(20_000)
        }
    }

    // MARK: - I2C helpers (chỉ gọi trên `queue`)

    private func writeVCP(_ service: CFTypeRef, _ s: IOAVServiceSymbols, code: UInt8, value: UInt16) -> Bool {
        var packet = DDCPacket.setVCP(code: code, value: value)
        for attempt in 0..<2 {
            if attempt > 0 { usleep(30_000) }
            let ok = packet.withUnsafeMutableBytes {
                s.write(service, DDCPacket.chipAddress, DDCPacket.hostSubAddress, $0.baseAddress!, UInt32($0.count))
            } == kIOReturnSuccess
            if ok { return true }
        }
        return false
    }

    private func readLuminance(_ service: CFTypeRef, _ s: IOAVServiceSymbols, attempts: Int) -> (current: UInt16, max: UInt16)? {
        for attempt in 0..<attempts {
            if attempt > 0 { usleep(30_000) }
            var request = DDCPacket.getVCPRequest(code: DDCPacket.luminanceCode)
            let wrote = request.withUnsafeMutableBytes {
                s.write(service, DDCPacket.chipAddress, DDCPacket.hostSubAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard wrote == kIOReturnSuccess else { continue }
            // DDC/CI yêu cầu chờ tối thiểu 40ms trước khi đọc phản hồi.
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let read = reply.withUnsafeMutableBytes {
                s.read(service, DDCPacket.chipAddress, DDCPacket.hostSubAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard read == kIOReturnSuccess else { continue }
            if let parsed = DDCPacket.parseGetVCPReply(reply, code: DDCPacket.luminanceCode) {
                return parsed
            }
        }
        return nil
    }

    private func readEDIDIdentity(_ service: CFTypeRef, _ s: IOAVServiceSymbols) -> DDCPacket.EDIDIdentity? {
        if let copy = s.copyEDID {
            var data: Unmanaged<CFData>?
            if copy(service, &data) == kIOReturnSuccess, let cf = data?.takeRetainedValue() {
                if let id = DDCPacket.parseEDID([UInt8](cf as Data)) { return id }
            }
        }
        // Fallback: đọc 16 byte đầu EDID qua I2C 0x50.
        var header = [UInt8](repeating: 0, count: 16)
        let status = header.withUnsafeMutableBytes {
            s.read(service, DDCPacket.edidAddress, 0x00, $0.baseAddress!, UInt32($0.count))
        }
        return status == kIOReturnSuccess ? DDCPacket.parseEDID(header) : nil
    }

    /// Liệt kê IOAVService của các cổng màn ngoài (DCPAVServiceProxy có Location = External).
    private static func externalServices(_ s: IOAVServiceSymbols) -> [CFTypeRef] {
        var result: [CFTypeRef] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External" else { continue }
            if let service = s.create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                result.append(service)
            }
        }
        return result
    }
}
