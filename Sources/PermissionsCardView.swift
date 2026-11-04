import SwiftUI
import AppKit

// MARK: - Permissions Card View (Centralized Permission Control Hub)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
public struct PermissionsCardView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    public init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar (Clickable to toggle collapse/expand)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    permissionsManager.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill((permissionsManager.allGranted ? Tone.good : Tone.warn).opacity(0.14))
                            .frame(width: 28, height: 28)

                        Image(systemName: permissionsManager.allGranted ? "checkmark.shield" : "exclamationmark.shield")
                            .font(.system(size: FS.title, weight: .regular))
                            .foregroundStyle(permissionsManager.allGranted ? Tone.good : Tone.warn)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(tr("Cấp quyền phần mềm", "Permissions Hub"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.primary)

                            if !permissionsManager.allGranted {
                                Text(tr("(\(permissionsManager.missingCount) quyền chưa cấp)", "(\(permissionsManager.missingCount) missing)"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(Tone.warn)
                            }
                        }

                        Text(permissionsManager.allGranted ? tr("Hệ thống đã nhận đầy đủ các quyền hoạt động", "All required system permissions granted") : tr("Bấm mũi tên để xem chi tiết & lý do cần cấp quyền", "Click arrow for details & required reasons"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(permissionsManager.allGranted ? Tone.good : Tone.bad)
                            .frame(width: 6, height: 6)
                        Text(permissionsManager.allGranted ? tr("Đầy đủ", "All granted") : tr("Thiếu quyền", "Missing"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(permissionsManager.allGranted ? Tone.good : Tone.bad)

                    // Chevron Down / Up
                    Image(systemName: permissionsManager.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                .padding(9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Permission Details
            if permissionsManager.isExpanded {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 4)

                    // 1. Accessibility (Trợ năng) - Bắt buộc
                    permissionRow(
                        title: tr("1. Quyền Trợ năng (Accessibility)", "1. Accessibility Permission"),
                        tag: tr("BẮT BUỘC", "REQUIRED"),
                        tagColor: .secondary,
                        icon: "hand.raised.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasAccessibility,
                        reason: tr("Cần thiết để nhận diện phím tắt chia cửa sổ (Rectangle), F1/F2 chỉnh sáng màn ngoài, chuyển tab AltTab và Cắt/Dán tệp Finder (⌘X ➔ ⌘V).", "Essential for window snapping (Rectangle), F1/F2 external brightness, AltTab switcher, and Finder Cut & Paste (⌘X ➔ ⌘V)."),
                        actionTitle: tr("Cấp quyền ngay", "Grant Now"),
                        action: {
                            permissionsManager.openAccessibilitySettings()
                        }
                    )

                    // 2. Screen Recording (Ghi màn hình) - Khuyên dùng
                    permissionRow(
                        title: tr("2. Quyền Ghi màn hình (Screen Recording)", "2. Screen Recording Permission"),
                        tag: tr("KHUYÊN DÙNG", "RECOMMENDED"),
                        tagColor: .secondary,
                        icon: "record.circle",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasScreenCapture,
                        reason: tr("Dùng để chụp ảnh thu nhỏ trực tiếp (Live Thumbnail) sắc nét của các cửa sổ khi bấm ⌘+Tab. (Nếu không cấp, AltTab vẫn dùng được nhưng chỉ hiện icon).", "Used for sharp live window previews in ⌘+Tab. (Without this, AltTab still functions using app icons)."),
                        actionTitle: tr("Mở Cài đặt", "Open Settings"),
                        action: {
                            permissionsManager.openScreenCaptureSettings()
                        }
                    )

                    // 3. SMC Helper (Khóa sạc 80%) - Phần cứng
                    permissionRow(
                        title: tr("3. Quản lý nguồn & Khóa sạc 80% (SMC)", "3. Power & Charge Limiter (SMC)"),
                        tag: tr("PHẦN CỨNG", "HARDWARE"),
                        tagColor: .secondary,
                        icon: "bolt.batteryblock.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasSMCHelper,
                        reason: tr("Giao tiếp trực tiếp với chip điều khiển nguồn SMC, tự động ngắt dòng điện khi pin đạt 80% để triệt tiêu nguy cơ chai pin, phồng pin.", "Communicates directly with SMC to stop charging at 80%, bypassing battery to prevent degradation."),
                        actionTitle: tr("Cài đặt Helper", "Install Helper"),
                        action: {
                            permissionsManager.installSMCHelper()
                        }
                    )

                    // 4. Bluetooth (Sleep Guard) - Tiết kiệm pin
                    permissionRow(
                        title: tr("4. Quyền Bluetooth (Sleep Guard)", "4. Bluetooth (Sleep Guard)"),
                        tag: tr("TIẾT KIỆM PIN", "BATTERY SAVER"),
                        tagColor: .secondary,
                        icon: "wave.3.forward.circle.fill",
                        iconColor: .secondary,
                        isGranted: permissionsManager.hasBluetooth,
                        reason: tr("Tự động ngắt kết nối Bluetooth khi gập màn hình máy Mac để chống tụt pin qua đêm (0% hao hụt pin).", "Automatically turns off Bluetooth when lid is closed to eliminate overnight battery drain (0% loss)."),
                        actionTitle: tr("Mở Cài đặt", "Open Settings"),
                        action: {
                            permissionsManager.openBluetoothSettings()
                        }
                    )
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
                .transition(.opacity)
            }
        }
        .cardBackground()
    }

    // MARK: - Single Permission Row Card

    private func permissionRow(
        title: String,
        tag: String,
        tagColor: Color,
        icon: String,
        iconColor: Color,
        isGranted: Bool,
        reason: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tag)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tagColor.opacity(0.12)))
                    .foregroundStyle(tagColor)

                Text(reason)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Cột trạng thái / hành động: rộng cố định theo nội dung, không xuống dòng.
            Group {
                if isGranted {
                    HStack(spacing: 5) {
                        Circle().fill(Tone.good).frame(width: 6, height: 6)
                        Text(tr("Đã cấp", "Granted"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Tone.good)
                } else {
                    Button {
                        action()
                    } label: {
                        HStack(spacing: 3) {
                            Text(actionTitle)
                                .font(.system(size: FS.caption, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: FS.caption))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Rad.sm)
                .fill(isGranted ? Color.primary.opacity(0.02) : Tone.warn.opacity(0.09))
        )
        .overlay(alignment: .leading) {
            if !isGranted {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Tone.warn)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
    }
}
