import Foundation
import CoreGraphics
import AppKit
import VirtualDisplayBridge

// MARK: - Virtual Display Resolution Model

public struct VirtualResolution: Identifiable, Equatable {
    public var id: String { "\(width)x\(height)@\(Int(refreshRate))" }
    public let name: String
    public let width: UInt
    public let height: UInt
    public let refreshRate: Double
    public let isHiDPI: Bool
}

// MARK: - Virtual Display Manager Engine

@MainActor
public class VirtualDisplayManager: ObservableObject {
    public static let shared = VirtualDisplayManager()

    @Published public var isVirtualDisplayActive: Bool = false
    @Published public var virtualDisplayID: CGDirectDisplayID = 0
    @Published public var selectedResolutionIndex: Int = 0 {
        didSet {
            UserDefaults.standard.set(selectedResolutionIndex, forKey: "virtual_display_res_idx")
            if isVirtualDisplayActive {
                reapplySettings()
            }
        }
    }
    @Published public var isHiDPIEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isHiDPIEnabled, forKey: "virtual_display_hidpi")
            if isVirtualDisplayActive {
                reapplySettings()
            }
        }
    }
    @Published public var isBlackoutPrimaryActive: Bool = false
    @Published public var isCardExpanded: Bool = false
    @Published public var statusMessage: String = tr("Màn hình ảo chưa bật", "Virtual display disabled")

    // Presets for Remote Desktop (Parsec, TeamViewer, Moonlight) & Mac mini Headless
    public let resolutions: [VirtualResolution] = [
        VirtualResolution(name: "1080p Full HD (1920 × 1080)", width: 1920, height: 1080, refreshRate: 60.0, isHiDPI: true),
        VirtualResolution(name: "2K QHD (2560 × 1440)", width: 2560, height: 1440, refreshRate: 60.0, isHiDPI: true),
        VirtualResolution(name: "4K UHD (3840 × 2160)", width: 3840, height: 2160, refreshRate: 60.0, isHiDPI: true),
        VirtualResolution(name: "MacBook 16:10 (1800 × 1169)", width: 1800, height: 1169, refreshRate: 60.0, isHiDPI: true),
        VirtualResolution(name: "iPad Retina 4:3 (2048 × 1536)", width: 2048, height: 1536, refreshRate: 60.0, isHiDPI: true),
        VirtualResolution(name: tr("1080p 120Hz Siêu mượt", "1080p 120Hz Ultra Smooth"), width: 1920, height: 1080, refreshRate: 120.0, isHiDPI: false)
    ]

    private var originalPrimaryBrightness: Float = 0.8

    private init() {
        let savedIdx = UserDefaults.standard.integer(forKey: "virtual_display_res_idx")
        if savedIdx >= 0 && savedIdx < resolutions.count {
            self.selectedResolutionIndex = savedIdx
        }
        if UserDefaults.standard.object(forKey: "virtual_display_hidpi") != nil {
            self.isHiDPIEnabled = UserDefaults.standard.bool(forKey: "virtual_display_hidpi")
        }
    }

    public var currentResolution: VirtualResolution {
        resolutions[selectedResolutionIndex]
    }

    // MARK: - Enable / Disable Virtual Display

    public func toggleVirtualDisplay() {
        if isVirtualDisplayActive {
            destroyVirtualDisplay()
        } else {
            createVirtualDisplay()
        }
    }

    public func createVirtualDisplay() {
        guard !isVirtualDisplayActive else { return }

        let res = currentResolution
        let id = VirtualDisplayBridge.shared().createDisplay(
            withName: "HyperMac Virtual Display",
            width: res.width,
            height: res.height,
            refreshRate: res.refreshRate,
            hiDPI: isHiDPIEnabled
        )

        guard id != 0 else {
            self.statusMessage = tr("Hệ thống không hỗ trợ tạo màn hình ảo", "System does not support virtual displays")
            return
        }

        self.virtualDisplayID = id
        self.isVirtualDisplayActive = true
        self.statusMessage = tr("Đang hoạt động (\(res.width)×\(res.height) @ \(Int(res.refreshRate))Hz)", "Active (\(res.width)×\(res.height) @ \(Int(res.refreshRate))Hz)")

        // Refresh DisplayManager to discover the new virtual screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DisplayManager.shared.refreshDisplays()
        }
    }

    public func destroyVirtualDisplay() {
        if isBlackoutPrimaryActive {
            restorePrimaryScreen()
        }
        VirtualDisplayBridge.shared().destroyDisplay()
        isVirtualDisplayActive = false
        virtualDisplayID = 0
        statusMessage = tr("Màn hình ảo đã tắt", "Virtual display turned off")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DisplayManager.shared.refreshDisplays()
        }
    }

    private func reapplySettings() {
        guard isVirtualDisplayActive else { return }
        let res = currentResolution
        let id = VirtualDisplayBridge.shared().createDisplay(
            withName: "HyperMac Virtual Display",
            width: res.width,
            height: res.height,
            refreshRate: res.refreshRate,
            hiDPI: isHiDPIEnabled
        )
        if id != 0 {
            self.virtualDisplayID = id
            self.statusMessage = tr("Đang hoạt động (\(res.width)×\(res.height) @ \(Int(res.refreshRate))Hz)", "Active (\(res.width)×\(res.height) @ \(Int(res.refreshRate))Hz)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                DisplayManager.shared.refreshDisplays()
            }
        }
    }

    // MARK: - Privacy Mode (Blackout Primary Screen for Remote WFH)

    public func toggleBlackoutPrimaryScreen() {
        if isBlackoutPrimaryActive {
            restorePrimaryScreen()
        } else {
            blackoutPrimaryScreen()
        }
    }

    public func blackoutPrimaryScreen() {
        guard !isBlackoutPrimaryActive else { return }
        if let primary = DisplayManager.shared.monitors.first(where: { $0.isBuiltIn }) {
            self.originalPrimaryBrightness = Float(primary.brightness)
            DisplayManager.shared.setBrightness(0.0, for: primary)
            self.isBlackoutPrimaryActive = true
        }
    }

    public func restorePrimaryScreen() {
        guard isBlackoutPrimaryActive else { return }
        if let primary = DisplayManager.shared.monitors.first(where: { $0.isBuiltIn }) {
            let target = self.originalPrimaryBrightness > 0.05 ? Double(self.originalPrimaryBrightness) : 0.75
            DisplayManager.shared.setBrightness(target, for: primary)
            self.isBlackoutPrimaryActive = false
        }
    }

    deinit {
        VirtualDisplayBridge.shared().destroyDisplay()
    }
}
