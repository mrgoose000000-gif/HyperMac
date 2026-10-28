import SwiftUI
import AppKit

// MARK: - Compact AltTab Overlay View (Genuine AltTab Style)

public struct AltTabOverlayView: View {
    @ObservedObject var windowManager: WindowManager

    public init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    private var selectedItem: WindowItem? {
        guard !windowManager.windows.isEmpty,
              windowManager.selectedIndex >= 0,
              windowManager.selectedIndex < windowManager.windows.count else {
            return nil
        }
        return windowManager.windows[windowManager.selectedIndex]
    }

    public var body: some View {
        ZStack {
            // Native HUD Glass Background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 24, y: 8)

            VStack(spacing: 8) {
                // 1. Top Minimal Status Header
                headerBar

                // 2. Center Horizontal Carousel of Window Cards
                cardsCarousel

                // 3. Bottom Keyboard Hints Bar
                footerHintsBar
            }
            .padding(.vertical, 10)
        }
        .frame(height: 225)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "command")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.cyan)
                Text("HYPERMAC")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
            }

            if let item = selectedItem {
                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.6))

                Text(item.appName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.cyan)

                if item.title != item.appName && !item.title.isEmpty {
                    Text("—")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(item.title)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if !windowManager.windows.isEmpty {
                Text("\(windowManager.selectedIndex + 1) / \(windowManager.windows.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    .foregroundStyle(Color.cyan)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - Cards Carousel (No giant review screen!)

    private var cardsCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(windowManager.windows.enumerated()), id: \.element.id) { index, item in
                        AltTabWindowTile(
                            item: item,
                            index: index,
                            isSelected: windowManager.selectedIndex == index,
                            onSelect: {
                                windowManager.selectedIndex = index
                                windowManager.commitSelection()
                            },
                            onClose: {
                                windowManager.selectedIndex = index
                                windowManager.closeSelectedWindow()
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: windowManager.selectedIndex) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(windowManager.selectedIndex, anchor: .center)
                }
            }
        }
        .frame(height: 145)
    }

    // MARK: - Footer Hints Bar

    private var footerHintsBar: some View {
        HStack(spacing: 12) {
            HintChip(icon: "command", text: "⌘⇥ / ⇧⇥ Di chuyển")
            HintChip(icon: "arrow.left.arrow.right", text: "~ Đảo chiều")
            HintChip(icon: "xmark.circle", text: "W Đóng")
            HintChip(icon: "power", text: "Q Thoát app")
            HintChip(icon: "escape", text: "⎋ Hủy")
            HintChip(icon: "checkmark.circle.fill", text: "Thả ⌘ Chọn")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }
}

// MARK: - Individual Window Tile (Genuine AltTab Style)

struct AltTabWindowTile: View {
    let item: WindowItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Background Tile
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.cyan.opacity(0.16) : Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? Color.cyan : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                VStack(spacing: 0) {
                    // Top Bar: Traffic lights & Close button
                    tileTopBar

                    // Center: Real Thumbnail OR Large Crisp App Icon
                    tileCenterContent

                    // Bottom: Single Clean Title Label (No duplicates!)
                    tileBottomLabel
                }
            }
            .frame(width: 185, height: 135)
            .shadow(color: isSelected ? Color.cyan.opacity(0.35) : Color.clear, radius: 8, y: 2)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var tileTopBar: some View {
        HStack(spacing: 4) {
            if item.isMinimized {
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("Thu nhỏ")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
            } else {
                HStack(spacing: 3.5) {
                    Circle().fill(Color.red.opacity(0.75)).frame(width: 5, height: 5)
                    Circle().fill(Color.yellow.opacity(0.75)).frame(width: 5, height: 5)
                    Circle().fill(Color.green.opacity(0.75)).frame(width: 5, height: 5)
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Đóng cửa sổ (W)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private var tileCenterContent: some View {
        ZStack {
            if let thumb = item.thumbnail {
                // Real Live Window Screenshot Preview
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 170, maxHeight: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Corner App Icon Badge
                VStack {
                    Spacer()
                    HStack {
                        Image(nsImage: item.icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            .padding(4)
                        Spacer()
                    }
                }
            } else {
                // Clean Genuine AltTab App Icon Mode (No bogus wallpaper!)
                VStack(spacing: 3) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 76)
        .padding(.horizontal, 6)
    }

    private var tileBottomLabel: some View {
        VStack(spacing: 1) {
            // Clean single title: If title equals app name, show app name only!
            let hasDistinctTitle = (item.title != item.appName) && !item.title.isEmpty

            Text(hasDistinctTitle ? item.title : item.appName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isSelected ? Color.cyan : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if hasDistinctTitle {
                Text(item.appName)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .padding(.bottom, 6)
    }
}

// MARK: - Hint Chip Component

struct HintChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Visual Effect NSViewRepresentable

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
