import Testing
import Foundation
import CoreGraphics
@testable import HyperMac

private let retina = DisplayResolution(width: 1470, height: 956, pixelWidth: 2940, pixelHeight: 1912)
private let large = DisplayResolution(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160)
private func option(_ id: Int32, _ hz: Int, _ resolution: DisplayResolution = retina) -> DisplayModeOption {
    .init(id: id, resolution: resolution, milliHertz: hz)
}

private final class FakeDisplayModes: DisplayModeBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [CGDirectDisplayID: DisplayModeCatalog]
    private let failure: CGError
    init(failure: CGError = .success) {
        self.failure = failure
        let modes = [option(1, 60000), option(2, 120000), option(3, 60000, large)]
        snapshots = [1: .init(current: modes[0], modes: modes), 2: .init(current: modes[1], modes: modes)]
    }
    func catalog(for display: CGDirectDisplayID) -> DisplayModeCatalog? {
        lock.lock(); defer { lock.unlock() }
        return snapshots[display]
    }
    func apply(_ mode: DisplayModeOption, to display: CGDirectDisplayID) -> CGError {
        lock.lock(); defer { lock.unlock() }
        guard failure == .success else { return failure }
        guard let snapshot = snapshots[display], snapshot.modes.contains(mode) else { return .illegalArgument }
        snapshots[display] = .init(current: mode, modes: snapshot.modes)
        return .success
    }
}

struct DisplayModeTests {
    @Test func distinguishRetinaAndLowResolutionModesAndDeduplicateEncodings() {
        let low = DisplayResolution(width: 1470, height: 956, pixelWidth: 1470, pixelHeight: 956)
        let current = option(7, 60000)
        let catalog = DisplayModeCatalog(current: current, modes: [option(1, 60000), option(2, 60000, low)])
        #expect(catalog.resolutions.count == 2)
        #expect(catalog.rates(for: retina) == [current])
        #expect(retina.isHiDPI)
        #expect(!low.isHiDPI)
    }

    @Test func fractionalAndUnspecifiedRefreshRatesRemainDistinct() {
        let catalog = DisplayModeCatalog(current: option(1, 60000), modes: [option(2, 59940), option(3, 0)])
        #expect(catalog.rates(for: retina).map(\.milliHertz) == [60000, 59940, 0])
        #expect(option(2, 59940).refreshTitle == "59.94 Hz")
        #expect(option(1, 60000).refreshTitle == "60 Hz")
        #expect(!option(3, 0).refreshTitle.contains("0 Hz"))
    }

    @Test func resolutionChangeKeepsRateWhenAvailableAndNeverInventsModes() {
        let catalog = DisplayModeCatalog(current: option(1, 120000), modes: [option(2, 60000, large), option(3, 100000, large)])
        #expect(catalog.preferredMode(for: large) == option(3, 100000, large))
        #expect(catalog.rates(for: large).count == 2)
        #expect(catalog.preferredMode(for: retina) == catalog.current)
        let absent = DisplayResolution(width: 800, height: 600, pixelWidth: 800, pixelHeight: 600)
        #expect(catalog.preferredMode(for: absent) == nil)
    }

    @Test func currentModeIsKeptWhenEnumerationOmitsIt() {
        let current = option(1, 60000)
        #expect(DisplayModeCatalog(current: current, modes: []).modes == [current])
    }

    @MainActor private func waitForChange(_ manager: DisplayModeManager) async throws {
        for _ in 0..<100 where manager.applyingDisplay != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(manager.applyingDisplay == nil)
    }

    @Test @MainActor func changesOnlyTargetDisplayAndCanUndo() async throws {
        let manager = DisplayModeManager(backend: FakeDisplayModes())
        manager.refresh(displays: [1, 2])
        let other = manager.catalogs[2]
        manager.selectResolution(large, for: 1)
        #expect(manager.applyingDisplay == 1)
        try await waitForChange(manager)
        #expect(manager.catalogs[1]?.current == option(3, 60000, large))
        #expect(manager.catalogs[2] == other)
        #expect(manager.previous[1] == option(1, 60000))
        manager.undo(for: 1)
        try await waitForChange(manager)
        #expect(manager.catalogs[1]?.current == option(1, 60000))
        #expect(manager.previous[1] == nil)
    }

    @Test @MainActor func rejectedModesKeepActualSelectionAndExposeError() async throws {
        let manager = DisplayModeManager(backend: FakeDisplayModes(failure: .failure))
        manager.refresh(displays: [1])
        manager.select(option(2, 120000), for: 1)
        try await waitForChange(manager)
        #expect(manager.catalogs[1]?.current == option(1, 60000))
        #expect(manager.errors[1] != nil)
        #expect(manager.previous.isEmpty)
    }

    @Test @MainActor func staleOrDisconnectedDisplayCannotBeChanged() async throws {
        let manager = DisplayModeManager(backend: FakeDisplayModes())
        manager.refresh(displays: [1, 2])
        manager.select(option(99, 240000), for: 1)
        #expect(manager.applyingDisplay == nil)
        manager.select(option(2, 120000), for: 1)
        manager.refresh(displays: [2])
        try await waitForChange(manager)
        #expect(manager.catalogs[1] == nil)
        #expect(manager.previous[1] == nil)
        #expect(manager.errors[1] == nil)
    }
}
