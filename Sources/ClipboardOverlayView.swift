import SwiftUI
import AppKit

// MARK: - Clipboard HUD Overlay View (Hallmark Liquid Glass Design)

public struct ClipboardOverlayView: View {
    @ObservedObject var manager: ClipboardManager

    public init(manager: ClipboardManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            // Visual Effect Background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 30, y: 10)

            VStack(spacing: 0) {
                // Top Search & Filter Header
                topSearchBar

                // Filter Category Bar
                categoryBar

                Divider().opacity(0.2)

                // List of Clips
                if manager.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    clipsListView
                }

                Divider().opacity(0.2)

                // Bottom Footer & Hotkey Hints
                footerBar
            }
        }
        .frame(width: 430, height: 520)
    }

    // MARK: - Top Search Bar

    private var topSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            TextField("Tìm kiếm clipboard... (1-9 để dán nhanh)", text: $manager.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .onSubmit {
                    manager.pasteSelectedItem()
                }

            if !manager.searchText.isEmpty {
                Button {
                    manager.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Close HUD Button
            Button {
                manager.hideHUD()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Đóng (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Category Filter Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach([ClipType.all, .text, .image, .url, .file, .color], id: \.self) { type in
                    Button {
                        manager.selectedFilter = type
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 9))
                            Text(type.title)
                                .font(.system(size: 9.5, weight: manager.selectedFilter == type ? .bold : .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(manager.selectedFilter == type ? Color.accentColor : Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(manager.selectedFilter == type ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Clips List View

    private var clipsListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 5) {
                    ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        clipRow(index: index, item: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Single Clip Row

    private func clipRow(index: Int, item: ClipItem) -> some View {
        let isSelected = manager.selectedIndex == index
        let isHovered = manager.hoveredItemID == item.id
        let shortcutDigit = index < 9 ? "\(index + 1)" : nil

        return Button {
            manager.pasteItem(item)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Quick Paste Number Badge (1..9) or Pin
                ZStack {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                    } else if let digit = shortcutDigit {
                        Text(digit)
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : .secondary)
                    } else {
                        Image(systemName: item.type.icon)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .padding(.top, 2)

                // Content Column
                VStack(alignment: .leading, spacing: 3) {
                    // Header: Source App + Timestamp
                    HStack(spacing: 4) {
                        if let appName = item.sourceAppName, !appName.isEmpty {
                            Text(appName)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        Text(item.relativeTimeText)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Action Buttons on Hover
                        if isHovered || isSelected {
                            HStack(spacing: 6) {
                                // Toggle Pin
                                Button {
                                    manager.togglePin(item)
                                } label: {
                                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(item.isPinned ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(item.isPinned ? "Bỏ ghim (⌥P)" : "Ghim lên đầu (⌥P)")

                                // Delete
                                Button {
                                    manager.deleteItem(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help("Xóa mục (⌥⌫)")
                            }
                        }
                    }

                    // Main Content Render by Type
                    switch item.type {
                    case .image:
                        if let imgData = item.imageData, let nsImg = NSImage(data: imgData) {
                            HStack(spacing: 8) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 160, maxHeight: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.detail)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                    case .color:
                        HStack(spacing: 8) {
                            if let hex = item.colorHex {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Text(item.detail)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }

                    case .file:
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                    case .url:
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.blue)
                                Text(item.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color.blue)
                                    .lineLimit(1)
                            }
                            Text(item.detail)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                    case .text, .rtf, .all:
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if let text = item.plainText, text != item.title {
                                Text(text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            manager.hoveredItemID = hovering ? item.id : nil
            if hovering {
                manager.selectedIndex = index
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Lịch sử Clipboard trống")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            Text("Hãy sao chép (⌘C) văn bản, hình ảnh hoặc tệp tin để lưu vào HyperMac.")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Footer Bar

    private var footerBar: some View {
        HStack {
            // Key hints
            HStack(spacing: 8) {
                legendItem(key: "↵", label: "Dán")
                legendItem(key: "1-9", label: "Nhanh")
                legendItem(key: "⌥P", label: "Ghim")
                legendItem(key: "⌥⌫", label: "Xóa")
                legendItem(key: "⎋", label: "Đóng")
            }

            Spacer()

            // Count & Clear button
            HStack(spacing: 6) {
                Text("\(manager.filteredItems.count) mục")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button("Xóa hết") {
                    manager.clearAllHistory()
                }
                .font(.system(size: 8.5, weight: .bold))
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.red.opacity(0.1)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    private func legendItem(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color Hex Initializer

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
