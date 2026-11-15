import Testing
import AppKit
import SwiftUI
@testable import HyperMac

struct VirtualDisplayPreviewTests {
    @Test @MainActor func ultrawideCardPreview() throws {
        guard let directory = ProcessInfo.processInfo.environment["HYPERMAC_VIRTUAL_DISPLAY_QA_OUT"] else { return }
        let manager = VirtualDisplayManager.shared
        // Layout QA only: do not create displays or change the user's mirroring arrangement.
        #expect(!manager.isVirtualDisplayActive)
        let previous = manager.selectedResolutionIndex
        let expanded = manager.isCardExpanded
        defer {
            manager.selectedResolutionIndex = previous
            manager.isCardExpanded = expanded
        }
        manager.isCardExpanded = true
        manager.selectedResolutionIndex = try #require(manager.resolutions.firstIndex { $0.width == 3440 && $0.height == 1440 })
        for width in [320, 380] {
            let view = NSHostingView(rootView: VirtualDisplayCardView()
                .padding(10).frame(width: CGFloat(width)).preferredColorScheme(.dark))
            view.frame = CGRect(x: 0, y: 0, width: width, height: 370)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.layoutIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("hypermac-ultrawide-\(width).png"))
            window.contentView = nil
        }
    }
}
