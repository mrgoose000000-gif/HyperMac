import Testing
import CoreGraphics
import Foundation
@testable import HyperMac

struct WindowRestoreTests {
    let original = CGRect(x: 140, y: 100, width: 800, height: 600)
    let half = CGRect(x: 0, y: 30, width: 960, height: 1050)

    @Test func repeatedSnapsKeepTheOriginalAndRestoreEndsSequence() {
        var history = WindowFrameHistory<Int>()
        let first = history.begin(1, current: original, target: half)
        history.settle(1, token: first, actual: half)
        let full = CGRect(x: 0, y: 30, width: 1920, height: 1050)
        _ = history.begin(1, current: half, target: full)
        #expect(history.original(for: 1) == original)
        let restore = history.begin(1, current: full, target: original, restoring: true)
        #expect(history.original(for: 1) == nil)
        history.settle(1, token: restore, actual: original)
        _ = history.begin(1, current: original, target: half)
        #expect(history.original(for: 1) == original)
    }
    @Test func separateWindowsAndManualChangesHaveSeparateOrigins() {
        var history = WindowFrameHistory<Int>()
        let token = history.begin(1, current: original, target: half)
        history.settle(1, token: token, actual: half)
        let second = CGRect(x: 220, y: 200, width: 900, height: 650)
        _ = history.begin(2, current: second, target: half)
        #expect(history.original(for: 1) == original)
        #expect(history.original(for: 2) == second)
        #expect(history.original(for: 3) == nil)
        _ = history.begin(1, current: second, target: half)
        #expect(history.original(for: 1) == second)
    }
    @Test func delayedSnapCannotOverrideRapidRestore() {
        var history = WindowFrameHistory<Int>()
        let snap = history.begin(1, current: original, target: half)
        let restore = history.begin(1, current: half, target: original, restoring: true)
        #expect(!history.isCurrent(1, token: snap))
        #expect(history.isCurrent(1, token: restore))
        history.settle(1, token: snap, actual: half)
        #expect(history.isCurrent(1, token: restore))
        #expect(history.original(for: 1) == nil)
    }
    @Test func constrainedAppFrameDoesNotOverwriteOriginal() {
        var history = WindowFrameHistory<Int>()
        let token = history.begin(1, current: original, target: half)
        let actual = CGRect(x: half.minX, y: half.minY, width: 1000, height: 1050)
        history.settle(1, token: token, actual: actual)
        _ = history.begin(1, current: actual, target: half)
        #expect(history.original(for: 1) == original)
    }
    @Test func restoreFitsDisconnectedScreenAndPreservesConnectedFrame() {
        let main = CGRect(x: 0, y: 30, width: 1440, height: 870)
        let external = CGRect(x: -1920, y: 30, width: 1920, height: 1050)
        let externalWindow = CGRect(x: -1800, y: 100, width: 1600, height: 950)
        #expect(WindowFrameHistory<Int>.visibleRestoreFrame(original, screens: [main], fallback: main) == original)
        #expect(WindowFrameHistory<Int>.visibleRestoreFrame(externalWindow, screens: [main, external], fallback: main) == externalWindow)
        let fitted = WindowFrameHistory<Int>.visibleRestoreFrame(externalWindow, screens: [main], fallback: main)
        #expect(main.contains(fitted))
        #expect(fitted.size == CGSize(width: 1440, height: 870))
    }
    @Test func closedWindowHistoryIsBounded() {
        var history = WindowFrameHistory<Int>(capacity: 2)
        for key in 1...3 { _ = history.begin(key, current: original, target: half) }
        #expect(history.original(for: 1) == nil)
        #expect(history.original(for: 2) == original)
        #expect(history.original(for: 3) == original)
    }
    @Test @MainActor func migrateCenterAliasesWithoutLosingCustomShortcuts() throws {
        let suite = "HyperMac.RestoreTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let co: CGEventFlags = [.maskControl, .maskAlternate]
        var old = Dictionary(uniqueKeysWithValues: ShortcutConfiguration().bindings.map { ($0.key.rawValue, $0.value) })
        old.removeValue(forKey: "restoreWindow")
        old["center"] = [8,51,117].map { ShortcutBinding(UInt16($0), co) }
        let custom = ShortcutBinding(17, [.maskCommand, .maskControl])
        old["screenshot"] = [custom]
        defaults.set(try JSONEncoder().encode(old), forKey: ShortcutManager.preferencesKey)
        let manager = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(manager.configuration.bindings[.screenshot] == [custom])
        #expect(manager.configuration.match(8, flags: co)?.action == .center)
        #expect(manager.configuration.match(51, flags: co)?.action == .restoreWindow)
        #expect(manager.configuration.match(117, flags: co) == nil)
        #expect(manager.set(.init(16, [.maskCommand, .maskControl]), action: .restoreWindow, index: 0) == nil)
        let reloaded = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(reloaded.configuration.match(51, flags: co) == nil)
        #expect(reloaded.configuration.match(16, flags: [.maskCommand, .maskControl])?.action == .restoreWindow)
    }
    @Test @MainActor func newRestoreDefaultDoesNotResetConflictingCustomPreferences() throws {
        let suite = "HyperMac.RestoreTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let co: CGEventFlags = [.maskControl, .maskAlternate]
        var old = Dictionary(uniqueKeysWithValues: ShortcutConfiguration().bindings.map { ($0.key.rawValue, $0.value) })
        old.removeValue(forKey: "restoreWindow")
        old["center"] = []
        old["clipboard"] = [.init(51, co)]
        defaults.set(try JSONEncoder().encode(old), forKey: ShortcutManager.preferencesKey)
        let manager = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(manager.configuration.match(51, flags: co)?.action == .clipboard)
        #expect(manager.configuration.bindings[.restoreWindow] == [])
        manager.disable(.clipboard)
        let reloaded = ShortcutManager(defaults: defaults, publishRuntime: false)
        #expect(reloaded.configuration.bindings[.restoreWindow] == [])
        #expect(reloaded.restore(.restoreWindow) == nil)
        #expect(reloaded.configuration.match(51, flags: co)?.action == .restoreWindow)
    }
}
