import SwiftUI
import AppKit

/// Design tokens dùng chung cho toàn bộ UI. Giữ ít bậc để giao diện gọn, nhất quán.
/// Quy ước: không dùng cỡ chữ < `FS.caption` (10pt); đậm chỉ dùng cho số lớn (>= `FS.value`).

/// Cỡ chữ (pt).
enum FS {
    static let caption: CGFloat = 10   // chú thích, gợi ý phụ
    static let label: CGFloat = 11     // nhãn, nút nhỏ, tag
    static let body: CGFloat = 12      // nội dung chính
    static let title: CGFloat = 13     // tiêu đề thẻ
    static let subhead: CGFloat = 14   // tiêu đề mục lớn
    static let value: CGFloat = 16     // số liệu nổi bật
    static let display: CGFloat = 22   // số lớn
    static let hero: CGFloat = 28
    static let huge: CGFloat = 32
    static let mega: CGFloat = 36
}

/// Bo góc.
enum Rad {
    static let sm: CGFloat = 6    // nút, chip, ô nhỏ
    static let md: CGFloat = 10   // thẻ
    static let lg: CGFloat = 14   // bảng lớn
}

/// Màu ngữ nghĩa: chỉ dùng màu khi nó mang ý nghĩa. Mọi thứ khác dùng accent hoặc xám.
enum Tone {
    static let accent = Color.accentColor   // bật / đang chọn / hành động chính
    /// Xanh lá dịu (không dùng systemGreen chói): sáng hơn một chút ở dark mode.
    static let good = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.40, green: 0.70, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.20, green: 0.48, blue: 0.32, alpha: 1)
    })                                      // đã cấp / ổn / hoàn tất
    static let warn = Color.orange          // cảnh báo
    static let bad = Color.red              // lỗi / nguy hiểm
    static let muted = Color.secondary      // icon và chữ phụ (mặc định cho icon)
}

/// Bố cục "tràn dòng": các phần tử tự xuống hàng theo từng mục (không bẻ chữ giữa chừng).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Bảng phím tắt 2 cột: mô tả bên trái, phím bên phải, các cột thẳng hàng.
struct ShortcutGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), alignment: .top)],
            alignment: .leading,
            spacing: 6
        ) { content() }
    }
}

/// Nền thẻ duy nhất cho toàn app: cùng màu, cùng bo góc, cùng viền mảnh.
extension View {
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
