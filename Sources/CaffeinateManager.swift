import Foundation
import IOKit
import IOKit.pwr_mgt
import AppKit
import Combine

public enum CaffeinateDuration: Int, CaseIterable, Identifiable {
    case indefinite = 0
    case min15 = 900
    case min30 = 1800
    case hour1 = 3600
    case hour2 = 7200

    public var id: Int { self.rawValue }

    public var title: String {
        switch self {
        case .indefinite: return tr("Vô hạn", "Infinite")
        case .min15: return "15m"
        case .min30: return "30m"
        case .hour1: return "1h"
        case .hour2: return "2h"
        }
    }
}

// MARK: - Caffeinate Manager (Native Apple IOKit Keep-Awake)

@MainActor
public class CaffeinateManager: ObservableObject {
    public static let shared = CaffeinateManager()

    @Published public var isActive: Bool = false
    @Published public var selectedDuration: CaffeinateDuration = .indefinite
    @Published public var remainingSeconds: Int = 0
    @Published public var remainingFormatted: String = ""

    private var assertionID: IOPMAssertionID = 0
    private var countdownTimer: Timer?

    private init() {
        // Register cleanup on app quit so assertion is never leaked
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.disable()
            }
        }
    }

    public func toggle() {
        if isActive {
            disable()
        } else {
            enable(duration: selectedDuration)
        }
    }

    public func enable(duration: CaffeinateDuration = .indefinite) {
        self.selectedDuration = duration

        if assertionID == 0 {
            let type = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            let reason = "HyperMac Keep-Awake (Anti-Sleep)" as CFString
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if result == kIOReturnSuccess {
                appLog("☕️ CaffeinateManager: Native IOKit display assertion active (ID: \(assertionID))")
            } else {
                appLog("⚠️ CaffeinateManager: Failed to create assertion (Error: \(result))")
            }
        }

        self.isActive = true
        self.remainingSeconds = duration.rawValue
        updateRemainingFormatted()

        countdownTimer?.invalidate()
        if duration != .indefinite {
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tick()
                }
            }
        }
    }

    public func disable() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if assertionID != 0 {
            let res = IOPMAssertionRelease(assertionID)
            appLog("☕️ CaffeinateManager: Display assertion released (Result: \(res == kIOReturnSuccess))")
            assertionID = 0
        }

        self.isActive = false
        self.remainingSeconds = 0
        self.remainingFormatted = ""
    }

    public func setDuration(_ duration: CaffeinateDuration) {
        self.selectedDuration = duration
        if isActive {
            enable(duration: duration)
        }
    }

    private func tick() {
        guard isActive, selectedDuration != .indefinite else { return }

        if remainingSeconds > 1 {
            remainingSeconds -= 1
            updateRemainingFormatted()
        } else {
            disable()
            // Send user notification when timer expires
            let script = "display notification \"Hết thời gian hẹn giờ giữ màn hình. Màn hình đã trở lại chế độ ngủ bình thường của macOS.\" with title \"☕️ Chống sleep màn kết thúc\""
            DispatchQueue.global(qos: .utility).async {
                _ = shell("osascript -e '\(script)'")
            }
        }
    }

    private func updateRemainingFormatted() {
        if selectedDuration == .indefinite {
            remainingFormatted = "∞"
            return
        }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        if hours > 0 {
            remainingFormatted = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            remainingFormatted = String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
