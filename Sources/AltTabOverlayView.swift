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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 28, y: 10)

            VStack(spacing: 8) {
                // 1. Top Minimal Status Header
                headerBar

                // 2. Center Multi-Row Grid of Window Cards
                cardsGrid

                // 3. Bottom Keyboard Hints Bar
                footerHintsBar
            }
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "command")
                    .font(.system(size: FS.body, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("HYPERMAC")
                    .font(.system(size: FS.label, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            if let item = selectedItem {
                Text("•")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary.opacity(0.6))

                Text(item.appName)
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                if item.title != item.appName && !item.title.isEmpty {
                    Text("—")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(item.title)
                        .font(.system(size: FS.label, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if windowManager.showOnlyCurrentScreenWindows {
                HStack(spacing: 3.5) {
                    Image(systemName: "display")
                        .font(.system(size: FS.caption))
                    Text(tr("Màn hình này", "This Display"))
                        .font(.system(size: FS.caption, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                .foregroundStyle(.secondary)
            }

            if !windowManager.windows.isEmpty {
                Text("\(windowManager.selectedIndex + 1) / \(windowManager.windows.count)")
                    .font(.system(size: FS.caption, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Cards Grid (Multi-Row Window Switcher)

    private var cardsGrid: some View {
        let (columns, _) = WindowManager.computeGrid(windowCount: windowManager.windows.count)
        let colCount = max(1, columns)
        let allItems = Array(windowManager.windows.enumerated())
        let rows = stride(from: 0, to: allItems.count, by: colCount).map {
            Array(allItems[$0..<min($0 + colCount, allItems.count)])
        }

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        HStack(spacing: 12) {
                            ForEach(rows[rowIndex], id: \.element.id) { index, item in
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

                            // Keep grid columns flush to the left on ragged last rows
                            if rows[rowIndex].count < colCount {
                                ForEach(0..<(colCount - rows[rowIndex].count), id: \.self) { _ in
                                    Color.clear
                                        .frame(width: 260, height: 188)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            .onChange(of: windowManager.selectedIndex) {
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(windowManager.selectedIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Footer Hints Bar

    private var footerHintsBar: some View {
        HStack(spacing: 12) {
            HintChip(icon: "command", text: tr("⌘⇥ / ⇧⇥ Di chuyển", "⌘⇥ / ⇧⇥ Navigate"))
            HintChip(icon: "arrow.up.and.down.and.arrow.left.and.right", text: tr("↑↓←→ Lưới hàng", "↑↓←→ Grid"))
            HintChip(icon: "xmark.circle", text: tr("W Đóng", "W Close"))
            HintChip(icon: "power", text: tr("Q Thoát app", "Q Quit App"))
            HintChip(icon: "escape", text: tr("⎋ Hủy", "⎋ Cancel"))
            HintChip(icon: "checkmark.circle.fill", text: tr("Thả ⌘ Chọn", "Release ⌘ Select"))
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
                RoundedRectangle(cornerRadius: Rad.lg, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: Rad.lg, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 2.5 : 1
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
            .frame(width: 260, height: 188)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.40) : Color.clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var tileTopBar: some View {
        HStack(spacing: 5) {
            if item.isMinimized {
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5.5, height: 5.5)
                    Text(tr("Thu nhỏ", "Minimized"))
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.10)))
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.75)).frame(width: 5.5, height: 5.5)
                    Circle().fill(Color.orange.opacity(0.75)).frame(width: 5.5, height: 5.5)
                    Circle().fill(Tone.good.opacity(0.75)).frame(width: 5.5, height: 5.5)
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(tr("Đóng cửa sổ (W)", "Close window (W)"))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var tileCenterContent: some View {
        ZStack {
            if let thumb = item.thumbnail {
                // Real Live Window Screenshot Preview
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 242, maxHeight: 114)
                    .clipShape(RoundedRectangle(cornerRadius: Rad.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                // Corner App Icon Badge
                VStack {
                    Spacer()
                    HStack {
                        Image(nsImage: item.icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .padding(6)
                        Spacer()
                    }
                }
            } else {
                // Clean Genuine AltTab App Icon Mode (No bogus wallpaper!)
                VStack(spacing: 4) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.3), radius: 5, y: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 118)
        .padding(.horizontal, 8)
    }

    private var tileBottomLabel: some View {
        VStack(spacing: 1.5) {
            // Clean single title: If title equals app name, show app name only!
            let hasDistinctTitle = (item.title != item.appName) && !item.title.isEmpty

            Text(hasDistinctTitle ? item.title : item.appName)
                .font(.system(size: FS.label, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if hasDistinctTitle {
                Text(item.appName)
                    .font(.system(size: FS.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 7)
    }
}

// MARK: - Hint Chip Component

struct HintChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: FS.label, weight: .medium))
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
