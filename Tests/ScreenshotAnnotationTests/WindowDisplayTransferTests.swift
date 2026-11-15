import Testing
import Foundation
import CoreGraphics
@testable import HyperMac

@MainActor
struct WindowDisplayTransferTests {
    let source = CGRect(x: 0, y: 30, width: 1920, height: 1080)
    let wide = CGRect(x: 1920, y: -200, width: 3440, height: 1440)

    func move(_ window: CGRect, _ mode: WindowDisplayTransferMode,
              to destination: CGRect? = nil) -> CGRect {
        WindowSnapManager.calculateCrossDisplayRect(window: window, source: source,
            destination: destination ?? wide, mode: mode)
    }

    @Test func ordinaryWindowHasDistinctSizesAndKeepsRelativeCenter() {
        let window = CGRect(x: 460, y: 220, width: 1000, height: 700)
        let kept = move(window, .keepSize)
        #expect(kept == CGRect(x: 3140, y: 170, width: 1000, height: 700))
        let scaled = move(window, .proportional)
        #expect(scaled.size == CGSize(width: 1792, height: 933))
        #expect(wide.contains(scaled))
        #expect(WindowSnapManager.calculateCrossDisplayRect(window: window, source: source, destination: wide) == kept)
        let back = WindowSnapManager.calculateCrossDisplayRect(window: kept, source: wide, destination: source, mode: .keepSize)
        #expect(back == window)
    }

    @Test func halvesAndCornersFollowSelectedMode() {
        let half = CGRect(x: 0, y: 30, width: 960, height: 1080)
        #expect(move(half, .keepSize) == CGRect(x: 1920, y: -200, width: 960, height: 1440))
        #expect(move(half, .proportional) == CGRect(x: 1920, y: -200, width: 1720, height: 1440))
        let corner = CGRect(x: 960, y: 570, width: 960, height: 540)
        #expect(move(corner, .keepSize) == CGRect(x: 4400, y: 700, width: 960, height: 540))
        #expect(move(corner, .proportional) == CGRect(x: 3640, y: 520, width: 1720, height: 720))
    }

    @Test func maximizedStaysMaximizedButLargeFloatingWindowDoesNot() {
        for mode in WindowDisplayTransferMode.allCases {
            #expect(move(source, mode) == wide)
        }
        let almostFull = CGRect(x: 48, y: 60, width: 1824, height: 1020)
        #expect(move(almostFull, .keepSize).size == almostFull.size)
        #expect(move(almostFull, .proportional) == wide)
    }

    @Test func smallDestinationFitsEvenBelowOldMinimumSize() {
        let destination = CGRect(x: -300, y: -500, width: 280, height: 200)
        let window = CGRect(x: 300, y: 180, width: 1000, height: 700)
        for mode in WindowDisplayTransferMode.allCases {
            let result = move(window, mode, to: destination)
            #expect(destination.contains(result))
            #expect(result.size == destination.size)
        }
    }

    @Test func portraitTransferDoesNotStretchHalfIntoTallStrip() {
        let portrait = CGRect(x: -1080, y: -500, width: 1080, height: 1920)
        let half = CGRect(x: 0, y: 30, width: 960, height: 1080)
        #expect(move(half, .keepSize, to: portrait) == CGRect(x: -1080, y: -80, width: 960, height: 1080))
        #expect(move(half, .proportional, to: portrait) == CGRect(x: -1080, y: -500, width: 540, height: 1920))
        let back = WindowSnapManager.calculateCrossDisplayRect(window: portrait, source: portrait, destination: source, mode: .keepSize)
        #expect(back == source)
    }

    @Test func negativeScreenOriginsAndSmallEdgeGapsArePreserved() {
        let window = CGRect(x: 2, y: 32, width: 1916, height: 1076)
        #expect(move(window, .keepSize) == CGRect(x: 1922, y: -198, width: 3436, height: 1436))
        let dest = CGRect(x: -1600, y: -1000, width: 1600, height: 900)
        let floating = CGRect(x: 200, y: 200, width: 700, height: 500)
        let result = move(floating, .keepSize, to: dest)
        #expect(result.size == floating.size)
        #expect(dest.contains(result))
    }

    @Test func invalidScreenGeometryLeavesWindowUnchanged() {
        let window = CGRect(x: 200, y: 200, width: 700, height: 500)
        for mode in WindowDisplayTransferMode.allCases {
            #expect(move(window, mode, to: .zero) == window)
            #expect(move(window, mode, to: CGRect(x: CGFloat.infinity, y: 0, width: 500, height: 500)) == window)
        }
    }

    @Test func preferencePersistsBothModesWithoutChangingShortcuts() throws {
        let suite = "HyperMac.DisplayTransferTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: ShortcutManager.preferencesKey)
        let settings = WindowDisplayTransferSettings(defaults: defaults)
        #expect(settings.mode == .keepSize)
        for mode in [WindowDisplayTransferMode.proportional, .keepSize] {
            settings.mode = mode
            #expect(WindowDisplayTransferSettings(defaults: defaults).mode == mode)
        }
        #expect(defaults.data(forKey: ShortcutManager.preferencesKey) == Data([1, 2, 3]))
        defaults.set("unknown-mode", forKey: WindowDisplayTransferSettings.preferencesKey)
        #expect(WindowDisplayTransferSettings(defaults: defaults).mode == .keepSize)
    }
}
