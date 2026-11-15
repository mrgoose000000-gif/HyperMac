// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreGraphics
import Combine

struct DisplayResolution: Hashable, Identifiable, Sendable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    var id: Self { self }
    var isHiDPI: Bool { pixelWidth > width || pixelHeight > height }
    var title: String { "\(width) × \(height)" + (isHiDPI ? " · HiDPI" : "") }
}

struct DisplayModeOption: Identifiable, Equatable, Sendable {
    let id: Int32
    let resolution: DisplayResolution
    /// Preserve fractional refresh rates, e.g. 59.94 versus 60 Hz. Zero means unspecified.
    let milliHertz: Int
    var refreshTitle: String {
        guard milliHertz > 0 else { return tr("Theo hệ thống", "System default") }
        let value = Double(milliHertz) / 1000
        let number = String(format: "%.3f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return number + " Hz"
    }
    init(id: Int32, resolution: DisplayResolution, milliHertz: Int) {
        self.id = id; self.resolution = resolution; self.milliHertz = max(0, milliHertz)
    }
    init(_ mode: CGDisplayMode) {
        self.init(id: mode.ioDisplayModeID,
                  resolution: .init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight),
                  milliHertz: mode.refreshRate.isFinite && mode.refreshRate > 0 ? Int((mode.refreshRate * 1000).rounded()) : 0)
    }
}

struct DisplayModeCatalog: Equatable, Sendable {
    let current: DisplayModeOption
    let modes: [DisplayModeOption]
    let isMirrored: Bool

    init(current: DisplayModeOption, modes: [DisplayModeOption], isMirrored: Bool = false) {
        self.current = current
        self.isMirrored = isMirrored
        // Current first: retain its exact mode ID when duplicate encodings exist.
        var unique: [DisplayModeOption] = []
        for mode in [current] + modes where mode.resolution.width > 0 && mode.resolution.height > 0 {
            if !unique.contains(where: { $0.resolution == mode.resolution && $0.milliHertz == mode.milliHertz }) {
                unique.append(mode)
            }
        }
        self.modes = unique
    }
    var resolutions: [DisplayResolution] {
        Array(Set(modes.map(\.resolution))).sorted {
            if $0.width != $1.width { return $0.width < $1.width }
            if $0.height != $1.height { return $0.height < $1.height }
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            return $0.pixelHeight > $1.pixelHeight
        }
    }
    func rates(for resolution: DisplayResolution) -> [DisplayModeOption] {
        modes.filter { $0.resolution == resolution }.sorted { $0.milliHertz > $1.milliHertz }
    }
    func preferredMode(for resolution: DisplayResolution) -> DisplayModeOption? {
        let options = rates(for: resolution)
        // Keep the refresh rate when possible, otherwise choose the closest supported rate.
        return options.first(where: { $0.milliHertz == current.milliHertz }) ?? options.min {
            abs($0.milliHertz - current.milliHertz) < abs($1.milliHertz - current.milliHertz)
        }
    }
}

protocol DisplayModeBackend: Sendable {
    func catalog(for display: CGDirectDisplayID) -> DisplayModeCatalog?
    func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) -> CGError
}

struct CoreGraphicsDisplayModeBackend: DisplayModeBackend {
    private func modes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        CGDisplayCopyAllDisplayModes(display, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
    }
    func catalog(for display: CGDirectDisplayID) -> DisplayModeCatalog? {
        guard CGDisplayIsOnline(display) != 0, CGDisplayIsActive(display) != 0,
              let current = CGDisplayCopyDisplayMode(display) else { return nil }
        return DisplayModeCatalog(current: .init(current), modes: modes(for: display)
            .filter { $0.isUsableForDesktopGUI() }.map(DisplayModeOption.init),
            isMirrored: CGDisplayIsInMirrorSet(display) != 0)
    }
    func apply(_ option: DisplayModeOption, to display: CGDirectDisplayID) -> CGError {
        guard CGDisplayIsOnline(display) != 0, CGDisplayIsActive(display) != 0 else { return .invalidConnection }
        // Resolve again immediately before applying: display modes can change after hot-plug/mirroring.
        guard let mode = modes(for: display).first(where: {
            $0.isUsableForDesktopGUI() && DisplayModeOption($0) == option
        }) else { return .illegalArgument }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return begin }
        let configure = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        guard configure == .success else {
            _ = CGCancelDisplayConfiguration(config)
            return configure
        }
        return CGCompleteDisplayConfiguration(config, .permanently)
    }
}

@MainActor
final class DisplayModeManager: ObservableObject {
    static let shared = DisplayModeManager()
    @Published private(set) var catalogs: [CGDirectDisplayID: DisplayModeCatalog] = [:]
    @Published private(set) var errors: [CGDirectDisplayID: String] = [:]
    @Published private(set) var previous: [CGDirectDisplayID: DisplayModeOption] = [:]
    @Published private(set) var applyingDisplay: CGDirectDisplayID?
    private let backend: any DisplayModeBackend
    private let queue = DispatchQueue(label: "com.hypermac.display-modes", qos: .userInitiated)
    private var connectedIDs: Set<CGDirectDisplayID> = []

    init(backend: any DisplayModeBackend = CoreGraphicsDisplayModeBackend()) { self.backend = backend }

    func refresh(displays: [CGDirectDisplayID]) {
        connectedIDs = Set(displays)
        var next: [CGDirectDisplayID: DisplayModeCatalog] = [:]
        for id in displays { next[id] = backend.catalog(for: id) }
        if catalogs != next { catalogs = next }
        errors = errors.filter { connectedIDs.contains($0.key) }
        previous = previous.filter { id, option in next[id]?.modes.contains(option) == true }
    }

    func selectResolution(_ resolution: DisplayResolution, for display: CGDirectDisplayID) {
        guard let option = catalogs[display]?.preferredMode(for: resolution) else { return }
        select(option, for: display)
    }

    func select(_ option: DisplayModeOption, for display: CGDirectDisplayID, undoing: Bool = false) {
        guard applyingDisplay == nil, let catalog = catalogs[display], catalog.modes.contains(option) else { return }
        guard option != catalog.current else { return }
        let original = catalog.current
        applyingDisplay = display
        errors[display] = nil
        let backend = self.backend
        queue.async { [weak self] in
            let result = backend.apply(option, to: display)
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyingDisplay = nil
                self.refresh(displays: Array(self.connectedIDs))
                guard self.connectedIDs.contains(display) else { return }
                if result == .success, let actual = self.catalogs[display]?.current,
                   actual.resolution == option.resolution && actual.milliHertz == option.milliHertz {
                    self.previous[display] = !undoing && self.catalogs[display]?.modes.contains(original) == true ? original : nil
                } else {
                    self.errors[display] = result == .success
                        ? tr("macOS chưa áp dụng chế độ đã chọn. Hãy thử chế độ khác.", "macOS did not apply that mode. Try another mode.")
                        : tr("Không đổi được chế độ màn hình (mã \(result.rawValue)). Hãy thử lại.", "Could not change display mode (code \(result.rawValue)). Try again.")
                }
            }
        }
    }

    func undo(for display: CGDirectDisplayID) {
        guard let option = previous[display] else { return }
        select(option, for: display, undoing: true)
    }
}
