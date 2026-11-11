import Foundation
import CoreGraphics
import IOKit

public typealias CGDisplayConfigRef = OpaquePointer

@_silgen_name("CGBeginDisplayConfiguration")
public func CGBeginDisplayConfiguration(_ config: UnsafeMutablePointer<CGDisplayConfigRef?>) -> CGError

@_silgen_name("CGCompleteDisplayConfiguration")
public func CGCompleteDisplayConfiguration(_ config: CGDisplayConfigRef?, _ option: CGConfigureOption) -> CGError

@_silgen_name("CGCancelDisplayConfiguration")
public func CGCancelDisplayConfiguration(_ config: CGDisplayConfigRef?) -> CGError

@_silgen_name("CGRestorePermanentDisplayConfiguration")
public func CGRestorePermanentDisplayConfiguration()

// MARK: - Dynamic SkyLight Private Framework Bindings

public typealias SLSConfigureDisplayEnabledFunc = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
public typealias SLSGetDisplayListFunc = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError

private let skyLightHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
}()

private let slsConfigureDisplayEnabledFn: SLSConfigureDisplayEnabledFunc? = {
    guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSConfigureDisplayEnabled") else {
        return nil
    }
    return unsafeBitCast(sym, to: SLSConfigureDisplayEnabledFunc.self)
}()

private let slsGetDisplayListFn: SLSGetDisplayListFunc? = {
    guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSGetDisplayList") else {
        return nil
    }
    return unsafeBitCast(sym, to: SLSGetDisplayListFunc.self)
}()

public func SLSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError {
    if let fn = slsConfigureDisplayEnabledFn {
        return fn(config, display, enabled)
    }
    return .failure
}

public func SLSGetDisplayList(_ maxDisplays: UInt32, _ displays: UnsafeMutablePointer<CGDirectDisplayID>?, _ count: UnsafeMutablePointer<UInt32>?) -> CGError {
    if let fn = slsGetDisplayListFn {
        return fn(maxDisplays, displays, count)
    }
    return CGGetOnlineDisplayList(maxDisplays, displays, count)
}

// MARK: - IOKit display name lookups
public let kIODisplayOnlyPreferredName: UInt32 = 0x00000200
public let kDisplayVendorIDKey = "DisplayVendorID"
public let kDisplayProductIDKey = "DisplayProductID"
public let kDisplayProductNameKey = "DisplayProductName"
public let kIOMainPort: mach_port_t = 0

@_silgen_name("IODisplayCreateInfoDictionary")
public func IODisplayCreateInfoDictionary(
    _ service: io_service_t,
    _ options: UInt32
) -> Unmanaged<CFDictionary>?

// MARK: - Shared In-Process AppleSMC Reader (Zero Subprocess, Zero Sudo)

/// Đọc trực tiếp khóa AppleSMC qua IOKit trong tiến trình (0 tiến trình con, không cần root).
/// Dùng lại kết nối `io_connect_t` an toàn đa luồng cho BatteryManager, ThermalManager, FanManager.
public final class AppleSMCClient: @unchecked Sendable {
    private var conn: io_connect_t = 0
    private let lock = NSLock()

    public init() {
        openIfNeeded()
    }

    deinit {
        lock.lock()
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
        lock.unlock()
    }

    private func openIfNeeded() {
        guard conn == 0 else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        if IOServiceOpen(svc, mach_task_self_, 0, &conn) != KERN_SUCCESS {
            conn = 0
        }
        IOObjectRelease(svc)
    }

    public static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        b[offset..<(offset + 4)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private func call(cmd: UInt8, key: UInt32 = 0, index: UInt32 = 0, size: UInt32 = 0) -> [UInt8]? {
        openIfNeeded()
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        withUnsafeBytes(of: key) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = cmd
        withUnsafeBytes(of: index) { inp.replaceSubrange(44..<48, with: $0) }
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        var kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        if kr != KERN_SUCCESS {
            IOServiceClose(conn)
            conn = 0
            openIfNeeded()
            guard conn != 0 else { return nil }
            outSize = 80
            kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        }
        return kr == KERN_SUCCESS && out[40] == 0 ? out : nil
    }

    /// Đọc mảng byte thô của khóa SMC (trả `nil` nếu khóa không tồn tại trên dòng máy này).
    public func readKeyBytes(_ keyName: String) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        let code = Self.fourCC(keyName)
        guard let info = call(cmd: 9, key: code) else { return nil }
        let sz = Int(Self.u32(info, 28))
        guard sz > 0 && sz <= 32, let val = call(cmd: 5, key: code, size: UInt32(sz)) else { return nil }
        return Array(val[48..<(48 + sz)])
    }
}
