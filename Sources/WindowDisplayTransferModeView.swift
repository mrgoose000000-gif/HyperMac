// SPDX-License-Identifier: GPL-3.0-only
// Hallmark · component: native radio picker · theme: HyperMac native · genre: modern-minimal
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4
// Native hover/focus/pressed/disabled states; selection is immediate, with no async loading.
import SwiftUI

struct WindowDisplayTransferModeView: View {
    @ObservedObject var settings: WindowDisplayTransferSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Khi chuyển sang màn hình khác", "When moving to another display"))
                .font(.system(size: FS.label, weight: .medium))
            Picker(tr("Kích thước cửa sổ khi chuyển màn hình", "Window size when moving across displays"), selection: $settings.mode) {
                Text(tr("Giữ kích thước cửa sổ", "Keep window size"))
                    .tag(WindowDisplayTransferMode.keepSize)
                Text(tr("Co giãn theo màn hình", "Scale with display"))
                    .tag(WindowDisplayTransferMode.proportional)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.system(size: FS.body))
            .accessibilityIdentifier("windowDisplayTransferMode")
            Text(settings.mode == .keepSize
                 ? tr("Giữ kích thước cửa sổ thường, thu nhỏ nếu không vừa. Cửa sổ bám mép hoặc phóng lớn thích ứng với màn đích.",
                      "Keep ordinary window sizes, shrinking only to fit. Edge-spanning or maximized windows adapt to the destination.")
                 : tr("Co giãn chiều rộng và chiều cao theo tỷ lệ màn đích. Giữ bố cục nửa màn hình hoặc góc màn hình.",
                      "Scale width and height with the destination display. Keep half-screen and corner layouts."))
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("Lưu tự động · Áp dụng từ lần chuyển màn tiếp theo", "Saved automatically · Applies on the next display move"))
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
