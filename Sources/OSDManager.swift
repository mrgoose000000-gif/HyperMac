import SwiftUI
import AppKit

// MARK: - OSD HUD View

public struct OSDView: View {
    public let title: String
    public let value: Double // 0.0 ... 1.0

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: value > 0.01 ? "sun.max.fill" : "sun.min")
                .font(.system(size: FS.mega, weight: .medium))
                .foregroundStyle(.primary)

            Text(title)
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(value))))
                }
            }
            .frame(height: 7)
            .padding(.horizontal, 4)
        }
        .padding(18)
        .frame(width: 170, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 15, y: 5)
        )
    }
}

// MARK: - OSD Manager

@MainActor
public class OSDManager {
    public static let shared = OSDManager()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    private init() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 170, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.ignoresMouseEvents = true
        p.hasShadow = false
        self.panel = p
    }

    public func show(title: String, brightness: Double, on screen: NSScreen?) {
        guard let panel = panel else { return }

        panel.contentView = NSHostingView(rootView: OSDView(title: title, value: brightness))

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        if let s = targetScreen {
            let screenRect = s.frame
            let x = screenRect.origin.x + (screenRect.width - 170) / 2
            let y = screenRect.origin.y + 140 // Positioned about 140px above bottom, just like native macOS HUD
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fadeOut()
            }
        }
    }

    private func fadeOut() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
