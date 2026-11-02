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
                            .fill((permissionsManager.allGranted ? Color.green : Color.red).opacity(0.14))
                            .frame(width: 28, height: 28)

                        Image(systemName: permissionsManager.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(permissionsManager.allGranted ? Color.green : Color.red)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(tr("Cấp quyền phần mềm", "Permissions Hub"))
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.primary)

                            if !permissionsManager.allGranted {
                                Text(tr("(\(permissionsManager.missingCount) quyền chưa cấp)", "(\(permissionsManager.missingCount) missing)"))
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }

                        Text(permissionsManager.allGranted ? tr("Hệ thống đã nhận đầy đủ các quyền hoạt động", "All required system permissions granted") : tr("Bấm mũi tên để xem chi tiết & lý do cần cấp quyền", "Click arrow for details & required reasons"))
                            .font(.system(size: 7.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status Pill
                    HStack(spacing: 3) {
                        Image(systemName: permissionsManager.allGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 8))
                        Text(permissionsManager.allGranted ? tr("Đầy đủ quyền", "All Granted") : tr("Chưa đủ quyền", "Permissions Missing"))
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((permissionsManager.allGranted ? Color.green : Color.red).opacity(0.12))
                    )
                    .foregroundStyle(permissionsManager.allGranted ? Color.green : Color.red)

                    // Chevron Down / Up
                    Image(systemName: permissionsManager.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
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
                        tagColor: .red,
                        icon: "hand.raised.fill",
                        iconColor: .orange,
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
                        tagColor: .blue,
                        icon: "record.circle",
                        iconColor: .cyan,
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
                        tagColor: .purple,
                        icon: "bolt.batteryblock.fill",
                        iconColor: .green,
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
                        tagColor: .teal,
                        icon: "wave.3.forward.circle.fill",
                        iconColor: .teal,
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(permissionsManager.allGranted ? Color(nsColor: .controlBackgroundColor) : Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    permissionsManager.allGranted ? Color.green.opacity(0.2) : Color.red.opacity(0.25),
                    lineWidth: 1
                )
        )
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text(tag)
                    .font(.system(size: 6.5, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tagColor.opacity(0.12)))
                    .foregroundStyle(tagColor)

                Spacer()

                if isGranted {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                        Text(tr("Đã cấp", "Granted"))
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.12)))
                } else {
                    Button {
                        action()
                    } label: {
                        HStack(spacing: 3) {
                            Text(actionTitle)
                                .font(.system(size: 8, weight: .bold))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 7))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Reason Text
            Text(reason)
                .font(.system(size: 7.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .padding(6.5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(isGranted ? 0.02 : 0.04))
        )
    }
}
