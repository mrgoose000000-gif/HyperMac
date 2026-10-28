import SwiftUI

// MARK: - Main MenuBar View (Tabbed & Organized Architecture)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
public struct MainView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var batteryManager: BatteryManager = BatteryManager.shared
    @ObservedObject var snapManager: WindowSnapManager = WindowSnapManager.shared
    @ObservedObject var windowManager: WindowManager = WindowManager.shared
    @ObservedObject var clipboardManager: ClipboardManager = ClipboardManager.shared
    @ObservedObject var caffeinateManager: CaffeinateManager = CaffeinateManager.shared
    @ObservedObject var updateManager: UpdateManager = UpdateManager.shared
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared

    public init(displayManager: DisplayManager) {
        self.displayManager = displayManager
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Modern Sleek Header Bar
                ModernHeaderBar(
                    batteryManager: batteryManager,
                    caffeinateManager: caffeinateManager,
                    updateManager: updateManager,
                    thermalManager: thermalManager,
                    onSelectThermal: {
                        displayManager.selectedMainTab = 1
                        thermalManager.selectedSection = 1
                    }
                )

                // Top Tab Navigation Bar
                TopTabBar(selectedTab: Binding<Int>(
                    get: { displayManager.selectedMainTab },
                    set: { displayManager.selectedMainTab = $0 }
                ))

                Divider().padding(.horizontal, 10)

                // Active Tab Content View
                Group {
                    switch displayManager.selectedMainTab {
                    case 0:
                        DisplaysTabView(
                            displayManager: displayManager,
                            caffeinateManager: caffeinateManager,
                            virtualDisplayManager: virtualDisplayManager
                        )
                    case 1:
                        HardwareCareTabView(
                            batteryManager: batteryManager,
                            thermalManager: thermalManager
                        )
                    case 2:
                        ShortcutsTabView(
                            displayManager: displayManager,
                            snapManager: snapManager,
                            windowManager: windowManager,
                            clipboardManager: clipboardManager
                        )
                    default:
                        DisplaysTabView(
                            displayManager: displayManager,
                            caffeinateManager: caffeinateManager,
                            virtualDisplayManager: virtualDisplayManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().padding(.horizontal, 10)

                // Minimal Footer
                FooterView(updateManager: updateManager)
            }

            // Update Modal Overlay
            if updateManager.showUpdateModal {
                UpdateModalView(updateManager: updateManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: updateManager.showUpdateModal)
        .frame(width: 380, height: 570)
        .alert(isPresented: Binding<Bool>(
            get: { displayManager.showAlert },
            set: { displayManager.showAlert = $0 }
        )) {
            Alert(
                title: Text("Thông báo"),
                message: Text(displayManager.alertMessage ?? ""),
                dismissButton: .default(Text("Đã hiểu"))
            )
        }
    }
}

// MARK: - Modern Compact Header Bar

struct ModernHeaderBar: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var caffeinateManager: CaffeinateManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    var onSelectThermal: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Logo & Title
            HStack(spacing: 6) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text("HyperMac")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                // Version Badge (Clickable to check for update)
                Button {
                    updateManager.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 3) {
                        Text("v\(UpdateManager.currentVersion)")
                            .font(.system(size: 8.5, weight: .bold))
                        if updateManager.hasNewUpdate {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            updateManager.hasNewUpdate
                            ? Color.green.opacity(0.18)
                            : Color.primary.opacity(0.08)
                        )
                    )
                    .foregroundStyle(updateManager.hasNewUpdate ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(updateManager.hasNewUpdate ? "Đã có bản mới! Bấm để cập nhật" : "Kiểm tra bản cập nhật mới")
            }

            Spacer()

            // Keep-awake Active Indicator
            if caffeinateManager.isActive {
                HStack(spacing: 3) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 8.5))
                    Text(caffeinateManager.remainingFormatted)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(Color.orange)
                .help("Chống sleep màn hình đang bật (\(caffeinateManager.remainingFormatted))")
            }

            // Live Thermal Chip
            if thermalManager.cpuAvgTemp > 0 {
                Button {
                    onSelectThermal?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 8))
                            .foregroundStyle(headerTempColor)
                        Text(String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp))
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(headerTempColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Nhiệt độ CPU hiện tại: \(String(format: "%.1f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp)). Bấm để mở kiểm soát nhiệt & quạt")
            }

            // Live Status Chip
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusColor.opacity(0.12)))

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("Thoát HyperMac")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var headerTempColor: Color {
        let temp = thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp
        if temp < 60.0 {
            return .green
        } else if temp < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var statusColor: Color {
        if batteryManager.isBypassActive {
            return .cyan
        } else if batteryManager.isCharging {
            return .green
        } else if batteryManager.isPluggedIn {
            return .orange
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if batteryManager.isBypassActive {
            return "🛡️ 80% AC Bypass"
        } else if batteryManager.isCharging {
            return "⚡️ Đang sạc"
        } else if batteryManager.isPluggedIn {
            return "🔌 Đã cắm điện"
        } else {
            return "🔋 Dùng pin (\(batteryManager.currentLevel)%)"
        }
    }
}

// MARK: - Top Tab Navigation Bar

struct TopTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 4) {
            tabButton(index: 0, title: "Màn hình", icon: "display")
            tabButton(index: 1, title: "Pin & Phần cứng", icon: "shield.checkered")
            tabButton(index: 2, title: "Phím tắt & Cửa sổ", icon: "keyboard")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: selectedTab == index ? .bold : .medium))
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(selectedTab == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TAB 0: Hardware Care, Battery & Thermal View

struct HardwareCareTabView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared

    var body: some View {
        VStack(spacing: 6) {
            // Segment Switcher: Pin & Nguồn vs Tản nhiệt & Quạt
            HStack(spacing: 4) {
                sectionButton(
                    index: 0,
                    title: "Pin & Nguồn SMC",
                    icon: "bolt.shield.fill"
                )
                sectionButton(
                    index: 1,
                    title: "Nhiệt độ & Cảm biến",
                    icon: "thermometer.sun.fill",
                    badge: thermalManager.cpuAvgTemp > 0 ? String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp) : nil
                )
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 12)
            .padding(.top, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if thermalManager.selectedSection == 0 {
                        BatteryCardView(batteryManager: batteryManager, onSelectThermalSection: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                thermalManager.selectedSection = 1
                            }
                        })
                    } else {
                        ThermalAndFanCardView(thermalManager: thermalManager)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionButton(index: Int, title: String, icon: String, badge: String? = nil) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                thermalManager.selectedSection = index
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 8.5, weight: thermalManager.selectedSection == index ? .bold : .medium))

                if let badge = badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(thermalManager.selectedSection == index ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                }
            }
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(thermalManager.selectedSection == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(thermalManager.selectedSection == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TAB 1: Displays View

struct DisplaysTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var caffeinateManager: CaffeinateManager
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // Caffeinate (Anti-Sleep) Control Card
                    CaffeinateCardView(caffeinateManager: caffeinateManager)

                    // Virtual Display (Dummy Screen for Remote Desktop / Headless)
                    VirtualDisplayCardView(virtualDisplayManager: virtualDisplayManager)

                    // F1/F2 cursor-based brightness setting
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("F1 / F2 chỉnh màn hình theo con trỏ chuột")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("Tự nhận diện màn hình trong hoặc ngoài để tăng giảm độ sáng")
                                .font(.system(size: 7.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { displayManager.isCursorBased },
                            set: { displayManager.isCursorBased = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                    // Display List
                    VStack(spacing: 8) {
                        if displayManager.monitors.isEmpty {
                            EmptyStateView()
                        } else {
                            ForEach(displayManager.monitors) { monitor in
                                DisplayCardView(
                                    monitor: monitor,
                                    displayManager: displayManager,
                                    isSelected: displayManager.selectedID == monitor.id
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Quick Actions Bar (Soft disconnect)
            QuickActionsBar(displayManager: displayManager)
        }
    }
}

// MARK: - Caffeinate (Anti-Sleep) Card View

struct CaffeinateCardView: View {
    @ObservedObject var caffeinateManager: CaffeinateManager

    var body: some View {
        VStack(spacing: 8) {
            // Main Row: Icon, Title, Badge, and Switch
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(caffeinateManager.isActive ? Color.orange.opacity(0.2) : Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(caffeinateManager.isActive ? Color.orange : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text("Chống sleep màn (Caffeinate)")
                            .font(.system(size: 11, weight: .semibold))

                        if caffeinateManager.isActive {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                                Text(caffeinateManager.remainingFormatted)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(Color.orange)
                        }
                    }

                    Text("Giữ màn hình luôn sáng như 'caffeinate -d' trong Terminal")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding<Bool>(
                    get: { caffeinateManager.isActive },
                    set: { _ in caffeinateManager.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            // Duration Selection Pills
            HStack(spacing: 6) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    Button {
                        caffeinateManager.setDuration(duration)
                    } label: {
                        Text(duration.title)
                            .font(.system(size: 9, weight: caffeinateManager.selectedDuration == duration ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(caffeinateManager.selectedDuration == duration
                                          ? (caffeinateManager.isActive ? Color.orange : Color.accentColor)
                                          : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(
                                caffeinateManager.selectedDuration == duration
                                ? Color.white
                                : Color.primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(caffeinateManager.isActive ? Color.orange.opacity(0.06) : Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(caffeinateManager.isActive ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - Virtual Display (Dummy Screen) Card View

struct VirtualDisplayCardView: View {
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared

    var body: some View {
        VStack(spacing: 8) {
            // Main Row: Icon, Title, Badge, Settings button, and Switch
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(virtualDisplayManager.isVirtualDisplayActive ? Color.purple.opacity(0.2) : Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)

                    Image(systemName: "display.2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(virtualDisplayManager.isVirtualDisplayActive ? Color.purple : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text("Màn hình ảo (Dummy Display)")
                            .font(.system(size: 11, weight: .semibold))

                        if virtualDisplayManager.isVirtualDisplayActive {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 5, height: 5)
                                Text("\(virtualDisplayManager.currentResolution.width)×\(virtualDisplayManager.currentResolution.height)")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                            .foregroundStyle(Color.purple)
                        }
                    }

                    Text(virtualDisplayManager.isVirtualDisplayActive
                         ? "Đang phát ảo · Tăng tốc GPU cho Parsec / TeamViewer"
                         : "Tạo màn hình ảo cho máy gập, Mac mini headless")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Expand / Collapse Settings Toggle Button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        virtualDisplayManager.isCardExpanded.toggle()
                    }
                } label: {
                    Image(systemName: virtualDisplayManager.isCardExpanded ? "chevron.up.circle.fill" : "gearshape")
                        .font(.system(size: 11.5))
                        .foregroundStyle(virtualDisplayManager.isCardExpanded ? Color.purple : Color.secondary)
                        .padding(4)
                        .background(Circle().fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help(virtualDisplayManager.isCardExpanded ? "Thu gọn tùy chọn" : "Tùy chỉnh độ phân giải, HiDPI, Bảo mật")

                Toggle("", isOn: Binding<Bool>(
                    get: { virtualDisplayManager.isVirtualDisplayActive },
                    set: { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            virtualDisplayManager.toggleVirtualDisplay()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            // Expanded Settings Panel
            if virtualDisplayManager.isCardExpanded || virtualDisplayManager.isVirtualDisplayActive {
                VStack(spacing: 7) {
                    Divider().opacity(0.4)

                    // Resolution Preset Header
                    HStack {
                        Text("ĐỘ PHÂN GIẢI MÀN HÌNH ẢO")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(virtualDisplayManager.currentResolution.width)×\(virtualDisplayManager.currentResolution.height) @ \(Int(virtualDisplayManager.currentResolution.refreshRate))Hz")
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.purple)
                    }

                    // Resolution Preset Grid (2 columns)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                        ForEach(Array(virtualDisplayManager.resolutions.enumerated()), id: \.offset) { index, res in
                            Button {
                                virtualDisplayManager.selectedResolutionIndex = index
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(virtualDisplayManager.selectedResolutionIndex == index ? Color.purple : Color.secondary.opacity(0.3))
                                        .frame(width: 4.5, height: 4.5)

                                    Text(res.name)
                                        .font(.system(size: 8, weight: virtualDisplayManager.selectedResolutionIndex == index ? .bold : .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(virtualDisplayManager.selectedResolutionIndex == index
                                              ? Color.purple.opacity(0.15)
                                              : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(virtualDisplayManager.selectedResolutionIndex == index
                                                ? Color.purple.opacity(0.5)
                                                : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Bottom Quick Options: HiDPI toggle & Blackout Screen (Privacy)
                    HStack(spacing: 6) {
                        // HiDPI toggle
                        Button {
                            virtualDisplayManager.isHiDPIEnabled.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: virtualDisplayManager.isHiDPIEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(virtualDisplayManager.isHiDPIEnabled ? Color.purple : Color.secondary)
                                Text("Retina (HiDPI)")
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help("HiDPI giúp hiển thị văn bản và icon siêu mịn chuẩn Retina")

                        Spacer()

                        // Blackout Primary Display for Remote Privacy
                        Button {
                            virtualDisplayManager.toggleBlackoutPrimaryScreen()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: virtualDisplayManager.isBlackoutPrimaryActive ? "eye.slash.fill" : "eye.slash")
                                    .font(.system(size: 9))
                                    .foregroundStyle(virtualDisplayManager.isBlackoutPrimaryActive ? Color.yellow : Color.secondary)
                                Text(virtualDisplayManager.isBlackoutPrimaryActive ? "Đang tắt màn thật" : "Tắt tối màn thật")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(virtualDisplayManager.isBlackoutPrimaryActive ? Color.yellow : Color.primary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(virtualDisplayManager.isBlackoutPrimaryActive ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Tắt tối đen màn hình máy thật để chống nhìn trộm khi bạn điều khiển từ xa qua Parsec / TeamViewer")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(virtualDisplayManager.isVirtualDisplayActive ? Color.purple.opacity(0.06) : Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(virtualDisplayManager.isVirtualDisplayActive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - TAB 2: Shortcuts & Window Controls View

struct ShortcutsTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var snapManager: WindowSnapManager
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var clipboardManager: ClipboardManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                // Accessibility Alert if not granted
                if !displayManager.hasAccessibility {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cần cấp quyền Trợ năng (Accessibility)")
                                .font(.system(size: 10, weight: .bold))
                            Text("Bật HyperMac trong Cài đặt hệ thống để phím tắt hoạt động.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Cấp quyền") {
                            displayManager.requestAccessibility()
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
                }

                // AltTab Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Chuyển đổi cửa sổ (Command + Tab)")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Thay thế AltTab với live preview độc lập & chuẩn MRU")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { windowManager.isAltTabEnabled },
                            set: { windowManager.isAltTabEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if windowManager.isAltTabEnabled {
                        // AltTab Shortcuts Guide
                        HStack(spacing: 6) {
                            shortcutPill(key: "⌘ + Tab", desc: "Chuyển tiếp")
                            shortcutPill(key: "⌘ + ~", desc: "Lùi lại")
                            shortcutPill(key: "W", desc: "Đóng cửa sổ")
                            shortcutPill(key: "Q", desc: "Thoát App")
                        }

                        if !windowManager.hasScreenRecording {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.cyan)
                                Text("Cần quyền Ghi màn hình để hiện ảnh chụp cửa sổ thực tế.")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cấp quyền") {
                                    windowManager.requestScreenRecordingPermission()
                                }
                                .font(.system(size: 8, weight: .semibold))
                                .controlSize(.mini)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.cyan.opacity(0.08)))
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // Window Snapping (Rectangle) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Chia cửa sổ & Đa màn hình (Rectangle)")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Bố trí cửa sổ nhanh với độ trễ 0ms")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { snapManager.isSnapEnabled },
                            set: { snapManager.isSnapEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if snapManager.isSnapEnabled {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                shortcutPill(key: "⌥⌃←", desc: "Nửa trái")
                                shortcutPill(key: "⌥⌃→", desc: "Nửa phải")
                                shortcutPill(key: "⌥⌃↑", desc: "Toàn màn hình")
                                shortcutPill(key: "⌥⌃↓", desc: "Căn giữa")
                            }
                            HStack(spacing: 6) {
                                shortcutPill(key: "⌥⌘→", desc: "Sang màn hình phải")
                                shortcutPill(key: "⌥⌘←", desc: "Sang màn hình trái")
                                Spacer()
                            }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // Clipboard Manager (Maccy Replacement) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Quản lý Clipboard (Thay thế Maccy)")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Lịch sử sao chép thông minh, tìm kiếm & dán tức thì")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { clipboardManager.isMonitoringEnabled },
                            set: { clipboardManager.isMonitoringEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if clipboardManager.isMonitoringEnabled {
                        // Shortcuts & Quick Actions
                        HStack(spacing: 6) {
                            shortcutPill(key: "⌘⇧C", desc: "Mở bảng HUD")
                            shortcutPill(key: "1..9", desc: "Dán tức thì")
                            shortcutPill(key: "⌥P", desc: "Ghim")
                            shortcutPill(key: "⌥⌫", desc: "Xóa")
                        }

                        // Storage limit + automatic cleanup options
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("Giới hạn:")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)

                                ForEach([50, 100, 200, 500], id: \.self) { count in
                                    optionChip("\(count)", selected: clipboardManager.maxItemsCount == count) {
                                        clipboardManager.maxItemsCount = count
                                    }
                                }
                                optionChip("∞", selected: clipboardManager.hasUnlimitedHistory) {
                                    clipboardManager.maxItemsCount = 0
                                }

                                Spacer()

                                Text("\(clipboardManager.items.count) mục lưu")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Text("Tự động xoá:")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)

                                ForEach([0, 7, 30, 90], id: \.self) { days in
                                    optionChip(days == 0 ? "Không" : "\(days) ngày",
                                               selected: clipboardManager.autoCleanupDays == days) {
                                        clipboardManager.autoCleanupDays = days
                                    }
                                }

                                Spacer()

                                Button {
                                    clipboardManager.cleanupNow()
                                } label: {
                                    Text("Dọn ngay")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                                        .foregroundStyle(Color.orange)
                                }
                                .buttonStyle(.plain)
                                .help("Xoá mục chưa ghim cũ hơn \(clipboardManager.autoCleanupDays > 0 ? "\(clipboardManager.autoCleanupDays) ngày" : "30 ngày")")

                                Button {
                                    clipboardManager.requestClearAllUnpinned()
                                } label: {
                                    Text(clipboardManager.pendingClearAllConfirm ? "Chắc chắn?" : "Xoá tất cả")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red.opacity(clipboardManager.pendingClearAllConfirm ? 0.22 : 0.10)))
                                        .foregroundStyle(Color.red)
                                }
                                .buttonStyle(.plain)
                                .help("Xoá mọi mục chưa ghim (bấm 2 lần để xác nhận)")
                            }

                            if let message = clipboardManager.cleanupMessage {
                                Text(message)
                                    .font(.system(size: 7.8, weight: .medium))
                                    .foregroundStyle(Color.orange.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            }

                            if clipboardManager.hasUnlimitedHistory {
                                Text(clipboardManager.autoCleanupDays == 0
                                     ? "Không giới hạn số mục: nên bật tự động xoá để tránh phình bộ nhớ."
                                     : "Không giới hạn số mục • tự động xoá sau \(clipboardManager.autoCleanupDays) ngày.")
                                    .font(.system(size: 7.5))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                            }
                        }

                        // Ignore passwords toggle
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.green)
                            Text("Tự động bỏ qua mật khẩu (1Password, Bitwarden, Keychain)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding<Bool>(
                                get: { clipboardManager.ignoreConcealedTypes },
                                set: { clipboardManager.ignoreConcealedTypes = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }

                        // Open HUD Button
                        Button {
                            clipboardManager.toggleHUD()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 8.5))
                                Text("Mở bảng Clipboard HUD (⌘ + ⇧ + C)")
                                    .font(.system(size: 8.5, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // Mouse Chording Card
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bấm đồng thời Chuột Trái + Phải mở F3")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Mở Mission Control ngay trên chuột mà không cần chạm bàn phím")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding<Bool>(
                        get: { displayManager.isMouseChordEnabled },
                        set: {
                            displayManager.isMouseChordEnabled = $0
                            UserDefaults.standard.set($0, forKey: "mouse_chord_enabled")
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func optionChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8.5, weight: selected ? .bold : .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func shortcutPill(key: String, desc: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(desc)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Display Card View

struct DisplayCardView: View {
    var monitor: DisplayInfo
    @ObservedObject var displayManager: DisplayManager
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack(spacing: 6) {
                Image(systemName: monitor.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
                    .foregroundStyle(monitor.isConnected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(monitor.resolution) • \(monitor.isBuiltIn ? "Màn hình chính" : "Màn hình ngoài")")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(round(monitor.brightness * 100)))%")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(monitor.isConnected ? Color.primary : Color.secondary)
            }

            if monitor.isConnected {
                // Brightness Slider
                Slider(
                    value: Binding<Double>(
                        get: { monitor.brightness },
                        set: { displayManager.setBrightness($0, for: monitor) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                // Presets
                HStack(spacing: 4) {
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { val in
                        Button("\(Int(val * 100))%") {
                            displayManager.setBrightness(val, for: monitor)
                        }
                        .font(.system(size: 7.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Disconnect toggle
                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        Text(monitor.isBuiltIn ? "Tắt màn" : "Ngắt mềm")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(monitor.isBuiltIn && !displayManager.canDisconnect(monitor))
                }
            } else {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text("Đang ngắt mềm (Đã tắt)")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 8, weight: .bold))
                            Text("Bật lại")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Quick Actions Bar

struct QuickActionsBar: View {
    @ObservedObject var displayManager: DisplayManager

    var body: some View {
        HStack(spacing: 8) {
            if let ext = displayManager.monitors.first(where: { !$0.isBuiltIn }) {
                Button {
                    displayManager.toggleConnection(for: ext)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ext.isConnected ? "display.slash" : "display")
                            .font(.system(size: 9))
                        Text(ext.isConnected ? "Ngắt màn ngoài" : "Bật màn ngoài")
                            .font(.system(size: 9, weight: ext.isConnected ? .regular : .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .foregroundStyle(ext.isConnected ? Color.primary : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if displayManager.monitors.contains(where: { !$0.isConnected }) {
                Button {
                    displayManager.connectAllDisplays()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8.5))
                        Text("Bật tất cả màn hình")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Không tìm thấy màn hình nào")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Battery Protection Card View (Hallmark-Disciplined & Un-Clipped)

struct BatteryCardView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var energyManager: ProcessEnergyManager = ProcessEnergyManager.shared
    var onSelectThermalSection: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Battery Level Bar + Target Limit Notch + Live Wattage
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline) {
                    HStack(spacing: 2) {
                        Text("\(batteryManager.currentLevel)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Live Wattage
                    if batteryManager.isBypassActive {
                        Text("🛡️ 0.0W (Nguồn AC trực tiếp)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan)
                    } else if batteryManager.isCharging {
                        Text(String(format: "⚡️ +%.1fW (Đang sạc)", batteryManager.wattage))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else if batteryManager.isPluggedIn {
                        Text("🔌 0.0W (Đã cắm sạc)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    } else {
                        let mins = batteryManager.timeRemaining
                        let timeStr = mins > 0 ? " • Còn ~\(mins / 60)h\(mins % 60)m" : ""
                        Text(String(format: "🔋 -%.1fW%@", batteryManager.wattage, timeStr))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Custom Progress Bar with Lock Notch
                GeometryReader { geo in
                    let width = geo.size.width
                    let levelFraction = min(1.0, max(0.0, Double(batteryManager.currentLevel) / 100.0))
                    let limitFraction = min(1.0, max(0.0, Double(batteryManager.chargeLimit) / 100.0))

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: batteryManager.isBypassActive
                                        ? [Color.cyan, Color.blue]
                                        : [Color.green, Color.mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, width * levelFraction), height: 8)

                        if batteryManager.isProtectionEnabled {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: 2.5, height: 12)
                                .offset(x: max(0, width * limitFraction - 1.25), y: 0)
                        }
                    }
                }
                .frame(height: 12)

                if batteryManager.isProtectionEnabled {
                    HStack {
                        Spacer()
                        Text("Ngưỡng khóa: \(batteryManager.chargeLimit)%")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // 4 Hardware Health & Telemetry Metrics (Clean 4-column row)
            HStack(spacing: 5) {
                metricChip(
                    icon: "heart.fill",
                    iconColor: .pink,
                    title: "Độ khỏe cell",
                    val: String(format: "%.1f%%", batteryManager.exactHealthPercent),
                    sub: "\(batteryManager.nominalCapacity)/\(batteryManager.designCapacity)"
                )
                metricChip(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .purple,
                    title: "Chu kỳ sạc",
                    val: "\(batteryManager.cycleCount) lần",
                    sub: "Thiết kế: 1000"
                )
                Button {
                    onSelectThermalSection?()
                } label: {
                    metricChip(
                        icon: "thermometer.medium",
                        iconColor: tempBadgeColor,
                        title: "Nhiệt độ pin",
                        val: String(format: "%.1f°C", batteryManager.temperature),
                        sub: tempStatusText + " ›",
                        valColor: tempBadgeColor
                    )
                }
                .buttonStyle(.plain)
                .help("Bấm để mở kiểm soát nhiệt độ & quạt")

                metricChip(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Củ sạc",
                    val: batteryManager.adapterWatts > 0 ? "\(batteryManager.adapterWatts)W" : "Dùng Pin",
                    sub: batteryManager.adapterWatts > 0 ? "USB-C PD" : "bq40z651"
                )
            }

            // High-Temperature Alert Banner
            if batteryManager.temperature >= batteryManager.tempAlertThreshold {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cảnh báo: Pin đang ấm (\(String(format: "%.1f°C", batteryManager.temperature)))!")
                            .font(.system(size: 9.5, weight: .bold)).foregroundStyle(.red)
                        Text("MacBook Air M2 không quạt. Hãy chuyển sang tab 'Đóng băng' để tạm dừng tiến trình nặng.")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
            }

            // Sub-Navigation Pills (4 Tabs: Nguồn SMC, Sleep Guard, Đóng băng CPU, Lịch hiệu chuẩn)
            HStack(spacing: 3) {
                subTabButton(index: 0, title: "Nguồn SMC", icon: "bolt.shield")
                subTabButton(index: 1, title: "Sleep Guard", icon: "moon.stars")
                subTabButton(index: 2, title: "Đóng băng", icon: "snowflake")
                subTabButton(index: 3, title: "Lịch hiệu chuẩn", icon: "calendar.badge.clock")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            // Sub-Tab Content
            switch batteryManager.selectedHardwareTab {
            case 0:
                powerOverviewSubTab
            case 1:
                sleepGuardSubTab
            case 2:
                processFreezeSubTab
            case 3:
                autoScheduledCalibrationSubTab
            default:
                powerOverviewSubTab
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(batteryManager.isBypassActive ? Color.cyan.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func metricChip(icon: String, iconColor: Color, title: String, val: String, sub: String, valColor: Color = .primary) -> some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2.5) {
                Image(systemName: icon).font(.system(size: 7.5)).foregroundStyle(iconColor)
                Text(title).font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(val).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(valColor)
            Text(sub).font(.system(size: 6.8)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private func subTabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            batteryManager.selectedHardwareTab = index
            if index == 2 {
                energyManager.refreshProcesses()
            }
        } label: {
            HStack(spacing: 2.5) {
                Image(systemName: icon).font(.system(size: 7.5))
                Text(title).font(.system(size: 8, weight: batteryManager.selectedHardwareTab == index ? .bold : .medium))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(batteryManager.selectedHardwareTab == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(batteryManager.selectedHardwareTab == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // SUB-TAB 0: NGUỒN SMC
    private var powerOverviewSubTab: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Khóa sạc ở \(batteryManager.chargeLimit)% (Chạy điện trực tiếp)")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Cắm sạc liên tục không chai pin (SMC Bypass)")
                        .font(.system(size: 7.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isProtectionEnabled },
                    set: { batteryManager.isProtectionEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isProtectionEnabled {
                HStack(spacing: 6) {
                    Text("Mức khóa:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach([70, 80, 90], id: \.self) { val in
                        Button {
                            batteryManager.chargeLimit = val
                        } label: {
                            Text("\(val)%\(val == 80 ? " (Chuẩn)" : "")")
                                .font(.system(size: 8, weight: batteryManager.chargeLimit == val ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(batteryManager.chargeLimit == val ? Color.accentColor : Color.primary.opacity(0.06)))
                                .foregroundStyle(batteryManager.chargeLimit == val ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button {
                    batteryManager.isTopUpActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: batteryManager.isTopUpActive ? "xmark.circle" : "bolt.fill")
                            .font(.system(size: 8))
                        Text(batteryManager.isTopUpActive ? "Hủy sạc 100% (Khóa lại)" : "⚡️ Sạc đầy 100% tạm thời")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(batteryManager.isTopUpActive ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundStyle(batteryManager.isTopUpActive ? Color.orange : Color.primary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Khi cần mang máy ra ngoài").font(.system(size: 7.5)).foregroundStyle(.tertiary)
            }

            // Toggles
            toggleRow(icon: "thermometer.sun.fill", iconColor: .orange, title: "Thông báo khi pin nóng > 38°C", isOn: Binding<Bool>(
                get: { batteryManager.isTempAlertEnabled },
                set: { batteryManager.isTempAlertEnabled = $0 }
            ))
            toggleRow(icon: "bell.badge.fill", iconColor: .blue, title: "Cảnh báo chống chai pin (Màn ngoài, pin < 20%)", isOn: Binding<Bool>(
                get: { batteryManager.isSmartAlertsEnabled },
                set: { batteryManager.isSmartAlertsEnabled = $0 }
            ))
        }
    }

    // SUB-TAB 1: SLEEP GUARD
    private var sleepGuardSubTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(Color.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bảo vệ Sleep Guard khi gập máy")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Chống Dark Wake và ngăn máy nóng ngầm trong balo")
                        .font(.system(size: 7.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isSleepGuardEnabled },
                    set: { batteryManager.isSleepGuardEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isSleepGuardEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.forward.circle.fill").font(.system(size: 10)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tự ngắt Bluetooth khi gập máy")
                            .font(.system(size: 9, weight: .medium))
                        Text("AirPods/chuột không đánh thức máy ngầm qua đêm. Tự bật lại ngay khi mở máy.")
                            .font(.system(size: 7.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding<Bool>(
                        get: { batteryManager.sleepGuardTurnOffBluetooth },
                        set: { batteryManager.sleepGuardTurnOffBluetooth = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 8.5)).foregroundStyle(.green)
                    Text("Khóa SMC 80% được bảo lưu liên tục trong lúc ngủ và tái kích hoạt ngay khi mở màn hình.")
                        .font(.system(size: 7.8)).foregroundStyle(.secondary)
                }

                if !batteryManager.lastSleepReport.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 8)).foregroundStyle(.purple)
                        Text("Lần gần nhất: \(batteryManager.lastSleepReport)")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.purple.opacity(0.08)))
                }
            }
        }
    }

    // SUB-TAB 2: PROCESS FREEZE
    private var processFreezeSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tiến trình ngốn CPU & Tỏa nhiệt:")
                    .font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Button {
                    energyManager.refreshProcesses()
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 7.5))
                        Text("Quét lại").font(.system(size: 8))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            if energyManager.processes.isEmpty {
                HStack {
                    Spacer()
                    Text("Máy đang rất mát mẻ, không có tiến trình nền nặng.")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 3.5) {
                    ForEach(energyManager.processes) { p in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(p.isFrozen ? Color.cyan : (p.cpu > 25.0 ? Color.red : Color.orange))
                                .frame(width: 5, height: 5)

                            VStack(alignment: .leading, spacing: 0.5) {
                                Text(p.name)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .lineLimit(1)
                                Text("PID: \(p.pid)")
                                    .font(.system(size: 6.8)).foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if p.isFrozen {
                                Text("❄️ ĐÃ ĐÓNG BĂNG")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
                            } else {
                                Text(String(format: "%.1f%% CPU", p.cpu))
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(p.cpu > 25.0 ? Color.red : Color.orange)
                            }

                            Button {
                                if p.isFrozen {
                                    energyManager.resumeProcess(pid: p.pid)
                                } else {
                                    energyManager.freezeProcess(pid: p.pid)
                                }
                            } label: {
                                Text(p.isFrozen ? "▶️ Rã đông" : "❄️ Đóng băng")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(p.isFrozen ? Color.green.opacity(0.15) : Color.cyan.opacity(0.15))
                                    .foregroundStyle(p.isFrozen ? Color.green : Color.cyan)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.03)))
                    }
                }
            }

            Text("💡 Đóng băng (SIGSTOP) giữ nguyên cửa sổ và dữ liệu trong RAM nhưng ngừng 100% việc đốt CPU và tỏa nhiệt trên M2.")
                .font(.system(size: 7.2)).foregroundStyle(.secondary)
        }
    }

    // SUB-TAB 3: AUTO-SCHEDULED BATTERY CALIBRATION (BMS)
    private var autoScheduledCalibrationSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Master Auto-Schedule Toggle
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Tự động đặt lịch hiệu chuẩn pin định kỳ")
                        .font(.system(size: 10, weight: .bold))
                    Text("Cân bằng điện áp cell & khôi phục thước đo dung lượng chuẩn")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isAutoCalibrationEnabled },
                    set: { batteryManager.isAutoCalibrationEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isAutoCalibrationEnabled {
                // Interval Selector Pills
                HStack(spacing: 5) {
                    Text("Chu kỳ:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach([30, 45, 60], id: \.self) { days in
                        Button {
                            batteryManager.calibrationIntervalDays = days
                        } label: {
                            Text("Mỗi \(days) ngày\(days == 30 ? " (Chuẩn)" : "")")
                                .font(.system(size: 7.5, weight: batteryManager.calibrationIntervalDays == days ? .bold : .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(batteryManager.calibrationIntervalDays == days ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(batteryManager.calibrationIntervalDays == days ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                // Schedule Info Box
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 8)).foregroundStyle(.orange)
                        Text("Lịch tiếp theo:")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(formatDate(batteryManager.nextScheduledCalibrationDate))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("Còn \(batteryManager.daysRemainingUntilCalibration) ngày")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }

                    HStack {
                        Image(systemName: "checkmark.circle").font(.system(size: 8)).foregroundStyle(.green)
                        Text("Lần gần nhất:")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(batteryManager.lastCalibrationDate != nil ? formatDate(batteryManager.lastCalibrationDate!) : "Chưa thực hiện")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.secondary)
                    }

                    Text("💡 Quy trình: Khi đến lịch, bạn rút sạc dùng máy tự nhiên xuống ≤ 20%. Khi cắm sạc lại, HyperMac sẽ tự động sạc 100% cân bằng cell ➔ ngâm 15p ➔ tự khóa lại 80% SMC Bypass.")
                        .font(.system(size: 7.2))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
            }

            // Action: Manual Run or Active Status
            if batteryManager.calibrationState == .idle {
                Button {
                    batteryManager.startCalibration()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle.fill").font(.system(size: 8.5))
                        Text("Hiệu chuẩn ngay bây giờ (Chạy trước lịch)")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 4) {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text(batteryManager.calibrationMessage)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.1)))

                    Button {
                        batteryManager.cancelCalibration()
                    } label: {
                        Text("Hủy hiệu chuẩn (Quay về khóa 80%)")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 8.5)).foregroundStyle(iconColor)
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private var tempBadgeColor: Color {
        if batteryManager.temperature < 32.0 {
            return .green
        } else if batteryManager.temperature < 38.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var tempStatusText: String {
        if batteryManager.temperature < 32.0 {
            return "Mát mẻ"
        } else if batteryManager.temperature < 38.0 {
            return "Ấm nhẹ"
        } else {
            return "Nóng!"
        }
    }
}

// MARK: - Thermal & Fan Control View (Macs Fan Control + Apple Silicon Thermal Suite)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct ThermalAndFanCardView: View {
    @ObservedObject var thermalManager: ThermalManager

    var body: some View {
        VStack(spacing: 8) {
            // 1. Device Profile & Thermal Health Header
            deviceHeaderCard

            // 2. Optional Menu Bar temperature pill
            menuBarMonitorRow

            // 3. Apple Silicon 6-Sensor Telemetry Matrix
            thermalMatrixGrid

            // 4. Detailed Sensor Breakdown (Expandable Accordion)
            detailedSensorsAccordion
        }
    }

    // MARK: - 1. Device Header Card
    private var deviceHeaderCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(headerIconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(headerIconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(thermalManager.machineModelName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("HID PMU")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }

                    Text("Cảm biến nhiệt Apple Silicon • Cập nhật mỗi 2.5s")
                        .font(.system(size: 7.8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Thermal State Pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 5, height: 5)
                    Text(thermalManager.thermalStateDescription)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(stateColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(stateColor.opacity(0.12)))

                // Refresh Button
                Button {
                    thermalManager.isRefreshing = true
                    thermalManager.refreshMetrics()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        thermalManager.isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(thermalManager.isRefreshing ? 360 : 0))
                        .animation(thermalManager.isRefreshing ? .linear(duration: 0.4) : .default, value: thermalManager.isRefreshing)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Làm mới cảm biến nhiệt ngay lập tức")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
    }

    // MARK: - 2. Menu Bar Monitor (temperature only)

    private var menuBarMonitorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.dock.rectangle")
                .font(.system(size: 9))
                .foregroundStyle(Color.accentColor)

            Text("Hiện nhiệt độ trên Menu Bar")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Spacer()

            if thermalManager.showMenuBarMetrics {
                Text("\(Int(thermalManager.cpuAvgTemp))°C")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cyan)
            }

            Toggle("", isOn: Binding<Bool>(
                get: { thermalManager.showMenuBarMetrics },
                set: { thermalManager.showMenuBarMetrics = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - 3. Apple Silicon Thermal Matrix (6 Core Metrics)
    private var thermalMatrixGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Bản đồ nhiệt Apple Silicon (HID PMU)", systemImage: "cpu")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Thời gian thực: 2.5s")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                sensorTile(
                    title: "CPU Trung bình",
                    temp: thermalManager.cpuAvgTemp,
                    icon: "cpu",
                    sub: "Tất cả các nhân"
                )
                sensorTile(
                    title: "CPU Nóng nhất",
                    temp: thermalManager.cpuPeakTemp,
                    icon: "flame.fill",
                    sub: "Core Peak Hotspot"
                )
                sensorTile(
                    title: "GPU Đồ họa",
                    temp: thermalManager.gpuAvgTemp,
                    icon: "gamecontroller.fill",
                    sub: "Cụm nhân GPU"
                )
                sensorTile(
                    title: "Pin Cell",
                    temp: thermalManager.batteryTemp,
                    icon: "battery.100.bolt",
                    sub: "Gas Gauge Pack"
                )
                sensorTile(
                    title: "Ổ cứng SSD",
                    temp: thermalManager.ssdTemp,
                    icon: "internaldrive.fill",
                    sub: "NAND Flash Storage"
                )
                sensorTile(
                    title: "Hotspot Bo mạch",
                    temp: thermalManager.hotspotTemp,
                    icon: "thermometer.sun.fill",
                    sub: "PMU Calibration"
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
    }

    private func sensorTile(title: String, temp: Double, icon: String, sub: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tempColor(temp))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(temp > 0 ? String(format: "%.1f°C", temp) : "—")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(tempColor(temp))

                Text(sub)
                    .font(.system(size: 6.8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - 4. Detailed Sensor Breakdown Accordion
    private var detailedSensorsAccordion: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    thermalManager.isDetailExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.accentColor)

                    Text("Chi tiết \(thermalManager.detailedSensors.count) cảm biến PMU trên chip")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: thermalManager.isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            if thermalManager.isDetailExpanded {
                VStack(spacing: 3) {
                    ForEach(thermalManager.detailedSensors) { s in
                        HStack {
                            Text(s.displayName)
                                .font(.system(size: 7.5, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("(\(s.name))")
                                .font(.system(size: 6.8))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(String(format: "%.1f°C", s.temp))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(tempColor(s.temp))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.02)))
            }
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        guard temp > 0 else { return .secondary }
        if temp < 55.0 {
            return .green
        } else if temp < 75.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var stateColor: Color {
        if thermalManager.isThrottling {
            return .red
        }
        let peak = thermalManager.cpuPeakTemp
        if peak < 60.0 {
            return .green
        } else if peak < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var headerIconColor: Color {
        Color.cyan
    }

    private var headerIconBackground: Color {
        Color.cyan.opacity(0.12)
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.green)
                Text("Open Source • Miễn phí")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Update Check / Action Button
            Button {
                updateManager.checkForUpdates(silent: false)
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: updateManager.hasNewUpdate ? "sparkles" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                    Text(updateManager.hasNewUpdate ? "Có bản v\(updateManager.latestVersionString)" : "Kiểm tra cập nhật")
                        .font(.system(size: 8.5, weight: updateManager.hasNewUpdate ? .bold : .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(updateManager.hasNewUpdate ? Color.green.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(updateManager.hasNewUpdate ? Color.green : Color.primary)
            }
            .buttonStyle(.plain)
            .help(updateManager.hasNewUpdate ? "Đã có bản mới! Bấm để cập nhật" : "Kiểm tra phiên bản mới từ GitHub")

            Button("Thoát") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 9.5))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

// MARK: - In-App Update Modal View

struct UpdateModalView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        ZStack {
            // Dimmed semi-transparent backdrop
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if case .downloading = updateManager.state {
                        // Prevent closing during download
                    } else if case .extracting = updateManager.state {
                        // Prevent closing
                    } else {
                        updateManager.showUpdateModal = false
                    }
                }

            // Modal Dialog Card
            VStack(spacing: 12) {
                // Header Bar
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Cập nhật HyperMac")
                                .font(.system(size: 12, weight: .bold))
                            Text("Phiên bản hiện tại: v\(UpdateManager.currentVersion)")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        updateManager.showUpdateModal = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // State Content
                switch updateManager.state {
                case .idle, .checking:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Đang kiểm tra bản cập nhật mới trên GitHub...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .upToDate(let ver):
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)

                        Text("Bạn đang dùng phiên bản mới nhất!")
                            .font(.system(size: 11.5, weight: .semibold))

                        Text("HyperMac v\(ver) hiện là phiên bản cập nhật nhất. Máy của bạn đã sẵn sàng.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        Button {
                            updateManager.checkForUpdates(silent: false)
                        } label: {
                            Text("Kiểm tra lại")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .updateAvailable(let ver, let notes, _, _):
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.cyan)

                            Text("Đã có phiên bản mới: v\(ver)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.cyan)
                        }

                        // Release Notes Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Điểm mới trong bản v\(ver):")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.vertical, showsIndicators: true) {
                                Text(notes)
                                    .font(.system(size: 9))
                                    .lineSpacing(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(height: 95)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }

                        // Action Buttons
                        VStack(spacing: 6) {
                            Button {
                                updateManager.startUpdate()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Cập nhật ngay (Tự động tải & Cài đặt)")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.accentColor)
                                )
                                .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text("Xem chi tiết trên GitHub")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                case .downloading(let progress):
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)

                        Text("Đang tải bản cập nhật: \(Int(progress * 100))%")
                            .font(.system(size: 11.5, weight: .semibold))

                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 20)

                        Text("HyperMac sẽ tự động thay thế và khởi động lại ngay sau khi tải xong.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .extracting, .readyToRestart:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)

                        Text("Đang cài đặt & chuẩn bị khởi động lại...")
                            .font(.system(size: 11, weight: .semibold))

                        Text("Ứng dụng sẽ tự động mở lại trong giây lát.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .failed(let errorMsg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)

                        Text("Không thể cập nhật tự động")
                            .font(.system(size: 11, weight: .semibold))

                        Text(errorMsg)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        HStack(spacing: 8) {
                            Button {
                                updateManager.checkForUpdates(silent: false)
                            } label: {
                                Text("Thử lại")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text("Mở GitHub Releases")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }

                Divider()

                // Preferences Row: Auto check on launch
                HStack {
                    Text("Tự động kiểm tra bản mới khi mở HyperMac")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Toggle("", isOn: Binding<Bool>(
                        get: { updateManager.autoCheckEnabled },
                        set: { updateManager.autoCheckEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}
