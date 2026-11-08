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
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject var finderCutPasteManager: FinderCutPasteManager = FinderCutPasteManager.shared
    @ObservedObject var cleanerManager: SystemCleanerManager = SystemCleanerManager.shared
    @ObservedObject var permissionsManager: PermissionsManager = PermissionsManager.shared
    @ObservedObject var languageManager: LanguageManager = LanguageManager.shared
    @ObservedObject var screenshotManager: ScreenshotManager = ScreenshotManager.shared
    @ObservedObject var activationManager: ActivationManager = ActivationManager.shared

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
                            permissionsManager: permissionsManager,
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
                            clipboardManager: clipboardManager,
                            caffeinateManager: caffeinateManager,
                            launchAtLoginManager: launchAtLoginManager,
                            finderCutPasteManager: finderCutPasteManager
                        )
                    case 3:
                        CleanerTabView(cleanerManager: cleanerManager)
                    default:
                        DisplaysTabView(
                            displayManager: displayManager,
                            permissionsManager: permissionsManager,
                            virtualDisplayManager: virtualDisplayManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().padding(.horizontal, 10)

                // Minimal Footer
                FooterView(updateManager: updateManager)
            }
            .id(languageManager.currentLanguage)

            // Update Modal Overlay
            if updateManager.showUpdateModal {
                UpdateModalView(updateManager: updateManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Donate Modal Overlay
            if updateManager.showDonateModal {
                DonateModalView(updateManager: updateManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Community Activation Modal Overlay (First launch required gate)
            if !activationManager.isActivated {
                ActivationModalView(activationManager: activationManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: updateManager.showUpdateModal || updateManager.showDonateModal || !activationManager.isActivated)
        .frame(width: 380, height: 570)
        .alert(isPresented: Binding<Bool>(
            get: { displayManager.showAlert },
            set: { displayManager.showAlert = $0 }
        )) {
            Alert(
                title: Text(tr("Thông báo", "Notice")),
                message: Text(displayManager.alertMessage ?? ""),
                dismissButton: .default(Text(tr("Đã hiểu", "OK")))
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
    @ObservedObject var languageManager: LanguageManager = LanguageManager.shared
    var onSelectThermal: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Logo & Title
            HStack(spacing: 6) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: FS.value, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text("HyperMac")
                    .font(.system(size: FS.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                // Version Badge (Clickable to check for update)
                Button {
                    updateManager.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 3) {
                        Text("v\(UpdateManager.currentVersion)")
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if updateManager.hasNewUpdate {
                            Circle()
                                .fill(Tone.good)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            updateManager.hasNewUpdate
                            ? Tone.good.opacity(0.10)
                            : Color.primary.opacity(0.08)
                        )
                    )
                    .foregroundStyle(updateManager.hasNewUpdate ? Tone.good : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(updateManager.hasNewUpdate ? tr("Đã có bản mới! Bấm để cập nhật", "New version available! Click to update") : tr("Kiểm tra bản cập nhật mới", "Check for updates"))

                // Language Switcher Badge (vi / en) — Directly to the right of version badge
                Button {
                    languageManager.promptLanguageSwitch()
                } label: {
                    Text(languageManager.currentLanguage == .vi ? "vi" : "en")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(languageManager.currentLanguage == .vi ? "Bấm để chuyển sang Tiếng Anh (English)" : "Click to switch to Vietnamese (Tiếng Việt)")
            }

            Spacer()

            // Live Thermal Chip
            if thermalManager.cpuAvgTemp > 0 {
                Button {
                    onSelectThermal?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: FS.caption))
                            .foregroundStyle(headerTempColor)
                        Text(String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp))
                            .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(tr("Nhiệt độ CPU hiện tại: \(String(format: "%.1f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp)). Bấm để mở kiểm soát nhiệt & quạt", "Current CPU temp: \(String(format: "%.1f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp)). Click for thermals & fan controls"))
            }

            // Live Status Chip
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(statusText)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(tr("Thoát HyperMac", "Quit HyperMac"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var headerTempColor: Color {
        let temp = thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp
        if temp < 60.0 {
            return Tone.good
        } else if temp < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var statusColor: Color {
        if batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn {
            return .accentColor
        } else if batteryManager.isCharging || (batteryManager.isPluggedIn && batteryManager.wattage > 0.05 && batteryManager.amperage > 0) {
            return Tone.good
        } else if batteryManager.isPluggedIn {
            return .secondary
        } else {
            return batteryManager.currentLevel <= 20 ? Tone.bad : .secondary
        }
    }

    private var statusIcon: String {
        if batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn {
            return "lock.shield.fill"
        } else if batteryManager.isCharging || (batteryManager.isPluggedIn && batteryManager.wattage > 0.05 && batteryManager.amperage > 0) {
            return "bolt.fill"
        } else if batteryManager.isPluggedIn {
            return "powerplug.fill"
        } else {
            return "battery.50"
        }
    }

    private var statusText: String {
        if batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn {
            return "\(batteryManager.chargeLimit)% Bypass"
        } else {
            return "\(batteryManager.currentLevel)%"
        }
    }
}

// MARK: - Top Tab Navigation Bar

struct TopTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 3) {
            tabButton(index: 0, title: tr("Màn hình", "Displays"), icon: "display")
            tabButton(index: 1, title: tr("Phần cứng", "Hardware"), icon: "bolt.batteryblock")
            tabButton(index: 2, title: tr("Phím tắt", "Shortcuts"), icon: "keyboard")
            tabButton(index: 3, title: tr("Dọn dẹp", "Cleaner"), icon: "sparkles")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: FS.caption, weight: .semibold))
                Text(title)
                    .font(.system(size: FS.caption, weight: selectedTab == index ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Rad.sm))
            .background(
                RoundedRectangle(cornerRadius: Rad.sm)
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
                    title: tr("Pin & Nguồn SMC", "Battery & Power SMC"),
                    icon: "bolt.shield.fill"
                )
                sectionButton(
                    index: 1,
                    title: tr("Nhiệt độ & Cảm biến", "Thermals & Sensors"),
                    icon: "thermometer.sun.fill",
                    badge: thermalManager.cpuAvgTemp > 0 ? String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp) : nil
                )
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Tốc độ truyền file (ổ vật lý + LAN/NAS) — luôn hiển thị
            FileTransferSpeedCard()
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
                Text(title)
                    .font(.system(size: FS.caption, weight: thermalManager.selectedSection == index ? .semibold : .medium))

                if let badge = badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(thermalManager.selectedSection == index ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                }
            }
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Rad.sm))
            .background(
                RoundedRectangle(cornerRadius: Rad.sm)
                    .fill(thermalManager.selectedSection == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(thermalManager.selectedSection == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Transfer Speed Card (ổ vật lý + LAN/NAS)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct FileTransferSpeedCard: View {
    @ObservedObject var diskSpeed: DiskSpeedManager = DiskSpeedManager.shared

    private var isActive: Bool {
        diskSpeed.totalReadMBps >= 0.05 || diskSpeed.totalWriteMBps >= 0.05 ||
        diskSpeed.networkReadMBps >= 0.05 || diskSpeed.networkWriteMBps >= 0.05
    }

    private var busiestDisk: DiskSpeedInfo? {
        diskSpeed.disks.filter(\.isActive).max { $0.totalMBps < $1.totalMBps }
    }

    /// Nguồn → đích của phiên chép đang chạy (ví dụ "U280-Pro → SSD nội bộ").
    /// Khi chỉ có một ổ vừa đọc vừa ghi thì hiện tên ổ đó.
    private var transferPath: String? {
        let reader = diskSpeed.disks
            .filter { $0.readMBps >= 1 }
            .max { $0.readMBps < $1.readMBps }
        let writer = diskSpeed.disks
            .filter { $0.writeMBps >= 1 }
            .max { $0.writeMBps < $1.writeMBps }

        switch (reader, writer) {
        case let (source?, destination?) where source.bsdName != destination.bsdName:
            return "\(source.displayName) → \(destination.displayName)"
        case let (_, destination?):
            return destination.displayName
        case let (source?, nil):
            return "\(tr("Đọc từ", "Reading from")) \(source.displayName)"
        default:
            return busiestDisk?.displayName
        }
    }

    private var networkActive: Bool {
        diskSpeed.networkReadMBps >= 0.05 || diskSpeed.networkWriteMBps >= 0.05
    }

    private var detailText: String? {
        var parts: [String] = []
        if let path = transferPath {
            parts.append(path)
        }
        if networkActive, let label = diskSpeed.networkLabel {
            parts.append("\(label) (NAS)")
        }
        if let process = diskSpeed.topProcessName {
            parts.append("\(process) \(speedText(max(diskSpeed.topProcessWriteMBps, diskSpeed.topProcessReadMBps)))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var tooltip: String {
        var lines = [tr("Tổng hợp mọi ổ vật lý đang đọc/ghi", "Aggregated active physical drives read/write")]
        for disk in diskSpeed.disks where disk.isActive {
            lines.append("\(disk.displayName): ↓\(speedText(disk.readMBps)) ↑\(speedText(disk.writeMBps))")
        }
        if let label = diskSpeed.networkLabel {
            lines.append("\(label): ↓\(speedText(diskSpeed.networkReadMBps)) ↑\(speedText(diskSpeed.networkWriteMBps))")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(diskSpeed.isEnabled && isActive ? Color.accentColor : Color.secondary)

                Text(diskSpeed.isEnabled ? tr("Chép file", "File Transfer") : tr("Đo tốc độ chép file", "Transfer Speed"))
                    .font(.system(size: FS.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if diskSpeed.isEnabled {
                    speedChip(icon: "arrow.down", value: diskSpeed.totalReadMBps, color: .accentColor)
                    speedChip(icon: "arrow.up", value: diskSpeed.totalWriteMBps, color: .secondary)

                    if diskSpeed.networkLabel != nil {
                        Divider().frame(height: 9)
                        speedChip(icon: "network", value: max(diskSpeed.networkReadMBps, diskSpeed.networkWriteMBps), color: .secondary)
                    }
                }

                Toggle("", isOn: Binding(
                    get: { diskSpeed.isEnabled },
                    set: { diskSpeed.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(diskSpeed.isEnabled
                      ? "Đang đo khi bảng này mở. Tắt để HyperMac ngừng quét hoàn toàn."
                      : "Bật để đo tốc độ chép file (ổ cứng, thẻ nhớ, NAS qua LAN).")
            }

            if diskSpeed.isEnabled, let detail = detailText {
                Text(detail)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardBackground()
        .help(diskSpeed.isEnabled ? tooltip : "Đo tốc độ chép file đang tắt")
        .animation(.easeOut(duration: 0.2), value: detailText)
    }

    private func speedChip(icon: String, value: Double, color: Color) -> some View {
        let active = value >= 0.05
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: FS.caption, weight: .semibold))
            Text(Self.speedText(value))
                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(active ? color : Color.secondary.opacity(0.7))
    }

    static func speedText(_ mbps: Double) -> String {
        if mbps >= 1024 { return String(format: "%.1f GB/s", mbps / 1024) }
        if mbps >= 10 { return String(format: "%.0f MB/s", mbps) }
        if mbps >= 0.1 { return String(format: "%.1f MB/s", mbps) }
        if mbps >= 0.01 { return String(format: "%.0f KB/s", mbps * 1024) }
        return "0 MB/s"
    }

    private func speedText(_ mbps: Double) -> String { Self.speedText(mbps) }
}

// MARK: - TAB 1: Displays View

struct DisplaysTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var permissionsManager: PermissionsManager = PermissionsManager.shared
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // Centralized Permissions Card Hub
                    PermissionsCardView(permissionsManager: permissionsManager)

                    // Virtual Display (Dummy Screen for Remote Desktop / Headless)
                    VirtualDisplayCardView(virtualDisplayManager: virtualDisplayManager)

                    // F1/F2 cursor-based brightness setting
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: FS.body))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("F1 / F2 chỉnh màn hình theo con trỏ chuột", "F1 / F2 controls brightness at mouse cursor"))
                                .font(.system(size: FS.label, weight: .medium))
                            Text(tr("Bật để chỉnh cả màn ngoài theo chuột; Tắt để dùng mặc định của macOS", "On: adjust display under cursor; Off: revert to native macOS controls"))
                                .font(.system(size: FS.caption))
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
                    .padding(.vertical, 8)
                    .cardBackground()

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

// MARK: - Menu Bar Drawer (Ngăn kéo gom ứng dụng Status Bar) Card View

// Hallmark · native settings component · existing Theme tokens
struct MenuBarHiderCardView: View {
    @AppStorage("menubar_drawer_details_expanded") private var showDetails = false
    @ObservedObject var manager = MenuBarHiderManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Ngăn kéo Menu Bar", "Menu Bar Drawer"))
                        .font(.system(size: FS.label, weight: .semibold))
                    Text(tr("Truy cập các mục Menu Bar trong một bảng riêng.", "Access menu bar items in a separate panel."))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showDetails.toggle() }
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.body, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help(showDetails ? tr("Ẩn chi tiết", "Hide details") : tr("Hiện chi tiết", "Show details"))
                .accessibilityLabel(showDetails ? tr("Ẩn chi tiết", "Hide details") : tr("Hiện chi tiết", "Show details"))
                Toggle(tr("Bật ngăn kéo", "Enable drawer"), isOn: $manager.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if showDetails {
                Divider()
                HStack {
                    Button { manager.toggle() } label: {
                        Label(manager.isExpanded ? tr("Đóng ngăn kéo", "Close drawer") : tr("Mở ngăn kéo", "Open drawer"), systemImage: "tray")
                    }
                    .controlSize(.small)
                    .disabled(!manager.isEnabled)
                    Spacer()
                    Text("⌘⌥B")
                        .font(.system(size: FS.caption, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(tr("Nhấn ⌥⌘B để mở bảng ứng dụng Menu Bar. Bấm ứng dụng để mở menu thật; kéo ☰ để đổi thứ tự icon trên thanh bar.", "Press ⌥⌘B to open menu bar apps. Click an app for its real menu; drag ☰ to reorder icons on the menu bar."))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .cardBackground()
    }
}

// MARK: - Caffeinate (Anti-Sleep) Card View

struct CaffeinateCardView: View {
    @AppStorage("caffeinate_details_expanded") private var showDetails = false
    @ObservedObject var caffeinateManager: CaffeinateManager

    var body: some View {
        VStack(spacing: 8) {
            // Main Row: Icon, Title, Badge, and Switch
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Rad.sm)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: FS.title, weight: .semibold))
                        .foregroundStyle(caffeinateManager.isActive ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(tr("Chống sleep màn", "Keep Screen Awake"))
                            .font(.system(size: FS.body, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if caffeinateManager.isActive {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                                Text(caffeinateManager.remainingFormatted)
                                    .font(.system(size: FS.caption, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text(tr("Giữ màn hình luôn sáng như 'caffeinate -d' trong Terminal", "Prevents display sleep, similar to 'caffeinate -d' in Terminal"))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showDetails.toggle() }
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.body, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help(showDetails ? tr("Ẩn chi tiết", "Hide details") : tr("Hiện chi tiết", "Show details"))
                .accessibilityLabel(showDetails ? tr("Ẩn chi tiết", "Hide details") : tr("Hiện chi tiết", "Show details"))
                Toggle("", isOn: Binding<Bool>(
                    get: { caffeinateManager.isActive },
                    set: { _ in caffeinateManager.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            // Collapsing details leaves the active assertion and timer unchanged.
            if showDetails {
            HStack(spacing: 6) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    Button {
                        caffeinateManager.setDuration(duration)
                    } label: {
                        Text(duration.title)
                            .font(.system(size: FS.caption, weight: caffeinateManager.selectedDuration == duration ? .semibold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm)
                                    .fill(caffeinateManager.selectedDuration == duration
                                          ? Color.accentColor
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
        }
        .padding(10)
        .cardBackground()
    }
}

// MARK: - Virtual Display (Dummy Screen) Card View

struct VirtualDisplayCardView: View {
    @ObservedObject var virtualDisplayManager: VirtualDisplayManager = VirtualDisplayManager.shared
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager.shared

    var body: some View {
        VStack(spacing: 8) {
            // Main Row: Icon, Title, Badge, Settings button, and Switch
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Rad.sm)
                        .fill(virtualDisplayManager.isVirtualDisplayActive ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)

                    Image(systemName: "display.2")
                        .font(.system(size: FS.title, weight: .semibold))
                        .foregroundStyle(virtualDisplayManager.isVirtualDisplayActive ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(tr("Màn hình ảo (Dummy Display)", "Virtual Display (Dummy Display)"))
                            .font(.system(size: FS.body, weight: .semibold))

                        if virtualDisplayManager.isVirtualDisplayActive {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                                Text("\(virtualDisplayManager.currentResolution.width)×\(virtualDisplayManager.currentResolution.height)")
                                    .font(.system(size: FS.caption, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                            .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(virtualDisplayManager.isVirtualDisplayActive
                         ? tr("Đang phát ảo · Tăng tốc GPU cho Parsec / TeamViewer", "Virtual screen active · GPU accelerated for Parsec / TeamViewer")
                         : tr("Tạo màn hình ảo cho máy gập, Mac mini headless", "Create dummy display for clamshell mode or headless Mac mini"))
                        .font(.system(size: FS.caption))
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
                        .font(.system(size: FS.body))
                        .foregroundStyle(virtualDisplayManager.isCardExpanded ? Color.accentColor : Color.secondary)
                        .padding(4)
                        .background(Circle().fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help(virtualDisplayManager.isCardExpanded ? tr("Thu gọn tùy chọn", "Collapse options") : tr("Tùy chỉnh độ phân giải, HiDPI, Bảo mật", "Customize resolution, HiDPI, Privacy"))

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
                        Text(tr("ĐỘ PHÂN GIẢI MÀN HÌNH ẢO", "VIRTUAL DISPLAY RESOLUTION"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(virtualDisplayManager.currentResolution.width)×\(virtualDisplayManager.currentResolution.height) @ \(Int(virtualDisplayManager.currentResolution.refreshRate))Hz")
                            .font(.system(size: FS.caption, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    }

                    // Resolution Preset Grid (2 columns)
                    resolutionGrid

                    // Bottom Quick Options: HiDPI toggle & Blackout Screen (Privacy)
                    quickOptionsRow
                }
            }
        }
        .padding(10)
        .cardBackground()
    }

    private var resolutionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
            ForEach(Array(virtualDisplayManager.resolutions.enumerated()), id: \.offset) { index, res in
                Button {
                    virtualDisplayManager.selectedResolutionIndex = index
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(virtualDisplayManager.selectedResolutionIndex == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 4.5, height: 4.5)

                        Text(res.name)
                            .font(.system(size: FS.caption, weight: virtualDisplayManager.selectedResolutionIndex == index ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: Rad.sm)
                            .fill(virtualDisplayManager.selectedResolutionIndex == index
                                  ? Color.accentColor.opacity(0.10)
                                  : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Rad.sm)
                            .stroke(virtualDisplayManager.selectedResolutionIndex == index
                                    ? Color.accentColor.opacity(0.5)
                                    : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickOptionsRow: some View {
        HStack(spacing: 6) {
            // HiDPI toggle
            Button {
                virtualDisplayManager.isHiDPIEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: virtualDisplayManager.isHiDPIEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(virtualDisplayManager.isHiDPIEnabled ? Color.accentColor : Color.secondary)
                    Text("Retina (HiDPI)")
                        .font(.system(size: FS.caption, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help(tr("HiDPI giúp hiển thị văn bản và icon siêu mịn chuẩn Retina", "HiDPI renders razor-sharp Retina text and icons"))

            Spacer()

            // Blackout Primary Display for Remote Privacy
            Button {
                virtualDisplayManager.toggleBlackoutPrimaryScreen()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: virtualDisplayManager.isBlackoutPrimaryActive ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(virtualDisplayManager.isBlackoutPrimaryActive ? Color.orange : Color.secondary)
                    Text(virtualDisplayManager.isBlackoutPrimaryActive ? tr("Đang tắt màn thật", "Primary Screen Off") : tr("Tắt tối màn thật", "Blackout Primary"))
                        .font(.system(size: FS.caption, weight: .medium))
                        .foregroundStyle(virtualDisplayManager.isBlackoutPrimaryActive ? Color.orange : Color.primary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: Rad.sm)
                        .fill(virtualDisplayManager.isBlackoutPrimaryActive ? Color.orange.opacity(0.10) : Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .help(tr("Tắt tối đen màn hình máy thật để chống nhìn trộm khi bạn điều khiển từ xa qua Parsec / TeamViewer", "Turn primary screen pitch black to prevent shoulder-surfing during remote sessions"))
        }
        .padding(.top, 2)
    }
}

// MARK: - TAB 2: Shortcuts & Window Controls View

struct ShortcutsTabView: View {
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var snapManager: WindowSnapManager
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var caffeinateManager: CaffeinateManager = CaffeinateManager.shared
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject var finderCutPasteManager: FinderCutPasteManager = FinderCutPasteManager.shared
    @ObservedObject var screenshotManager: ScreenshotManager = ScreenshotManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                // Accessibility Alert if not granted
                if !displayManager.hasAccessibility {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: FS.subhead))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Cần cấp quyền Trợ năng (Accessibility)", "Accessibility Permission Required"))
                                .font(.system(size: FS.label, weight: .semibold))
                            Text(tr("Bật HyperMac trong Cài đặt hệ thống để phím tắt hoạt động.", "Enable HyperMac in System Settings to allow shortcut interception."))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(tr("Cấp quyền", "Grant")) {
                            displayManager.requestAccessibility()
                        }
                        .font(.system(size: FS.caption, weight: .semibold))
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.orange.opacity(0.12)))
                }

                // Launch at Login Card
                HStack(spacing: 8) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: FS.title))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Khởi động cùng macOS", "Launch at Login"))
                            .font(.system(size: FS.label, weight: .semibold))
                        Text(tr("Tự động chạy HyperMac ngay khi đăng nhập vào máy Mac", "Automatically start HyperMac upon logging in"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding<Bool>(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .padding(10)
                .cardBackground()

                // Caffeinate (Anti-Sleep) Control Card
                CaffeinateCardView(caffeinateManager: caffeinateManager)

                // Menu Bar Hider (Gom gọn thanh Status Bar) Card
                MenuBarHiderCardView()

                // Finder Cut & Paste (Windows-style ⌘X ➔ ⌘V) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.system(size: FS.body, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Cắt & Dán tệp trong Finder (⌘X ➔ ⌘V)", "Finder Cut & Paste (⌘X ➔ ⌘V)"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(tr("Cắt và di chuyển tệp như trên Windows (bấm ⌘X để cắt, ⌘V để di chuyển)", "Cut & move files Windows-style (press ⌘X to cut, ⌘V to move)"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if finderCutPasteManager.isEnabled {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    finderCutPasteManager.isDetailsExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: finderCutPasteManager.isDetailsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(finderCutPasteManager.isDetailsExpanded ? 0.08 : 0.04)))
                            }
                            .buttonStyle(.plain)
                            .help(finderCutPasteManager.isDetailsExpanded ? tr("Thu gọn chi tiết", "Collapse details") : tr("Xem chi tiết phím tắt", "View shortcut details"))
                        }

                        Toggle("", isOn: Binding<Bool>(
                            get: { finderCutPasteManager.isEnabled },
                            set: { finderCutPasteManager.isEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if finderCutPasteManager.isEnabled && finderCutPasteManager.isDetailsExpanded {
                        Divider().opacity(0.35)

                        VStack(spacing: 5) {
                            ShortcutGrid {
                                shortcutPill(key: "⌘ + X", desc: tr("Cắt tệp / thư mục", "Cut file / folder"))
                                shortcutPill(key: "⌘ + V", desc: tr("Di chuyển đến đây", "Move here"))
                                shortcutPill(key: "esc", desc: tr("Huỷ cắt", "Cancel cut"))
                                shortcutPill(key: "⌘ + C", desc: tr("Chuyển sang Copy", "Switch to Copy"))
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                Text(tr("Tự động nhận diện khi đổi tên hoặc tìm kiếm: vẫn cắt văn bản bình thường.", "Smart context: text cutting remains untouched while renaming or searching."))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(10)
                .cardBackground()

                // AltTab Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: FS.body))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Chuyển cửa sổ (⌘ Tab)", "Window Switcher (⌘ Tab)"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(tr("Thay thế AltTab với live preview độc lập & chuẩn MRU", "AltTab replacement with live preview & MRU order"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if windowManager.isAltTabEnabled {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    windowManager.isDetailsExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: windowManager.isDetailsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(windowManager.isDetailsExpanded ? 0.08 : 0.04)))
                            }
                            .buttonStyle(.plain)
                            .help(windowManager.isDetailsExpanded ? tr("Thu gọn chi tiết", "Collapse details") : tr("Xem chi tiết phím tắt", "View shortcut details"))
                        }

                        Toggle("", isOn: Binding<Bool>(
                            get: { windowManager.isAltTabEnabled },
                            set: { windowManager.isAltTabEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if windowManager.isAltTabEnabled && windowManager.isDetailsExpanded {
                        Divider().opacity(0.35)

                        // Multi-monitor screen isolation toggle
                        HStack(spacing: 6) {
                            Image(systemName: "display.2")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(tr("Chỉ hiện cửa sổ trên màn hình hiện tại", "Only show windows on current display"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                Text(tr("Lọc riêng các cửa sổ thuộc màn hình con trỏ chuột đang đứng", "Filter windows belonging to the display where cursor is located"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding<Bool>(
                                get: { windowManager.showOnlyCurrentScreenWindows },
                                set: { windowManager.showOnlyCurrentScreenWindows = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)

                        // AltTab Shortcuts Guide
                        ShortcutGrid {
                            shortcutPill(key: "⌘ + Tab", desc: tr("Chuyển tiếp", "Forward"))
                            shortcutPill(key: "⌘ + ~", desc: tr("Lùi lại", "Backward"))
                            shortcutPill(key: "↑↓←→", desc: tr("Duyệt lưới", "Grid nav"))
                            shortcutPill(key: "W", desc: tr("Đóng", "Close"))
                            shortcutPill(key: "Q", desc: tr("Thoát App", "Quit App"))
                        }

                        if !windowManager.hasScreenRecording {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                Text(tr("Cần quyền Ghi màn hình để hiện ảnh chụp cửa sổ thực tế.", "Screen Recording permission needed for actual window snapshots."))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(tr("Cấp quyền", "Grant")) {
                                    windowManager.requestScreenRecordingPermission()
                                }
                                .font(.system(size: FS.caption, weight: .semibold))
                                .controlSize(.mini)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.accentColor.opacity(0.08)))
                        }
                    }
                }
                .padding(10)
                .cardBackground()

                // Window Snapping (Rectangle) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: FS.body))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Chia cửa sổ", "Window Snapping"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(tr("Bố trí cửa sổ nhanh với độ trễ 0ms", "Instant window positioning with 0ms latency"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if snapManager.isSnapEnabled {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    snapManager.isDetailsExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: snapManager.isDetailsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(snapManager.isDetailsExpanded ? 0.08 : 0.04)))
                            }
                            .buttonStyle(.plain)
                            .help(snapManager.isDetailsExpanded ? tr("Thu gọn chi tiết", "Collapse details") : tr("Xem chi tiết phím tắt", "View shortcut details"))
                        }

                        Toggle("", isOn: Binding<Bool>(
                            get: { snapManager.isSnapEnabled },
                            set: { snapManager.isSnapEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if snapManager.isSnapEnabled && snapManager.isDetailsExpanded {
                        Divider().opacity(0.35)

                        VStack(spacing: 5) {
                            ShortcutGrid {
                                shortcutPill(key: "⌃⌥←", desc: tr("Nửa trái", "Left Half"))
                                shortcutPill(key: "⌃⌥→", desc: tr("Nửa phải", "Right Half"))
                                shortcutPill(key: "⌃⌥↑", desc: tr("Nửa trên", "Top Half"))
                                shortcutPill(key: "⌃⌥↓", desc: tr("Nửa dưới", "Bottom Half"))
                            }
                            ShortcutGrid {
                                shortcutPill(key: "⌃⌥↩", desc: tr("Toàn màn hình", "Maximize"))
                                shortcutPill(key: "⌃⌥C / ⌃⌥⌫", desc: tr("Căn giữa", "Center"))
                                shortcutPill(key: "⌃⌥←↑/U", desc: tr("4 góc", "Quarters"))
                            }
                            ShortcutGrid {
                                shortcutPill(key: "⌥⌘→", desc: tr("Sang màn hình phải", "Next Display"))
                                shortcutPill(key: "⌥⌘←", desc: tr("Sang màn hình trái", "Previous Display"))
                            }
                        }
                    }
                }
                .padding(10)
                .cardBackground()

                // Clipboard Manager (Maccy Replacement) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: FS.body))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Lịch sử Clipboard", "Clipboard History"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(tr("Lịch sử sao chép thông minh, tìm kiếm & dán tức thì", "Smart clipboard history, search & instant paste"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if clipboardManager.isMonitoringEnabled {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    clipboardManager.isDetailsExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: clipboardManager.isDetailsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(clipboardManager.isDetailsExpanded ? 0.08 : 0.04)))
                            }
                            .buttonStyle(.plain)
                            .help(clipboardManager.isDetailsExpanded ? tr("Thu gọn chi tiết", "Collapse details") : tr("Xem chi tiết cài đặt", "View settings details"))
                        }

                        Toggle("", isOn: Binding<Bool>(
                            get: { clipboardManager.isMonitoringEnabled },
                            set: { clipboardManager.isMonitoringEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if clipboardManager.isMonitoringEnabled && clipboardManager.isDetailsExpanded {
                        Divider().opacity(0.35)

                        // Shortcuts & Quick Actions
                        ShortcutGrid {
                            shortcutPill(key: clipboardManager.hudShortcut.displayShort, desc: tr("Mở bảng HUD", "Open HUD"))
                            shortcutPill(key: "1..9", desc: tr("Dán tức thì", "Instant Paste"))
                            shortcutPill(key: "⌥P", desc: tr("Ghim", "Pin"))
                            shortcutPill(key: "⌥⌫", desc: tr("Xóa", "Delete"))
                        }

                        // Storage limit + automatic cleanup + HUD shortcut options
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text(tr("Phím mở:", "Open key:"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)

                                optionChip("⌘⇧C", selected: clipboardManager.hudShortcut == .cmdShiftC) {
                                    clipboardManager.hudShortcut = .cmdShiftC
                                }
                                optionChip("⌘⇧V", selected: clipboardManager.hudShortcut == .cmdShiftV) {
                                    clipboardManager.hudShortcut = .cmdShiftV
                                }

                                Spacer()
                            }

                            HStack(spacing: 4) {
                                Text(tr("Giới hạn:", "Max items:"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)

                                ForEach([50, 100, 200, 500], id: \.self) { count in
                                    optionChip("\(count)", selected: clipboardManager.maxItemsCount == count) {
                                        clipboardManager.maxItemsCount = count
                                    }
                                }
                                optionChip("∞", selected: clipboardManager.hasUnlimitedHistory) {
                                    clipboardManager.maxItemsCount = 0
                                }

                                Spacer()

                                Text("\(clipboardManager.items.count) " + tr("mục lưu", "items stored"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Text(tr("Tự động xoá:", "Auto cleanup:"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)

                                ForEach([0, 7, 30, 90], id: \.self) { days in
                                    optionChip(days == 0 ? tr("Không", "Never") : "\(days) " + tr("ngày", "days"),
                                               selected: clipboardManager.autoCleanupDays == days) {
                                        clipboardManager.autoCleanupDays = days
                                    }
                                }

                            }

                            HStack(spacing: 8) {
                                Button {
                                    clipboardManager.cleanupNow()
                                } label: {
                                    Text(tr("Dọn ngay", "Clean now"))
                                        .font(.system(size: FS.caption, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))
                                        .foregroundStyle(Color.primary)
                                }
                                .buttonStyle(.plain)
                                .help(tr("Xoá mục chưa ghim cũ hơn \(clipboardManager.autoCleanupDays > 0 ? "\(clipboardManager.autoCleanupDays) ngày" : "30 ngày")", "Delete unpinned items older than \(clipboardManager.autoCleanupDays > 0 ? "\(clipboardManager.autoCleanupDays) days" : "30 days")"))

                                Button {
                                    clipboardManager.requestClearAllUnpinned()
                                } label: {
                                    Text(clipboardManager.pendingClearAllConfirm ? tr("Chắc chắn?", "Confirm?") : tr("Xoá tất cả", "Clear all"))
                                        .font(.system(size: FS.caption, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(clipboardManager.pendingClearAllConfirm ? Color.red.opacity(0.14) : Color.primary.opacity(0.06)))
                                        .foregroundStyle(Tone.bad)
                                }
                                .buttonStyle(.plain)
                                .help(tr("Xoá mọi mục chưa ghim (bấm 2 lần để xác nhận)", "Delete all unpinned items (click twice to confirm)"))
                            }

                            if let message = clipboardManager.cleanupMessage {
                                Text(message)
                                    .font(.system(size: FS.caption, weight: .medium))
                                    .foregroundStyle(Color.orange.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            }

                            if clipboardManager.hasUnlimitedHistory {
                                Text(clipboardManager.autoCleanupDays == 0
                                     ? tr("Không giới hạn số mục: nên bật tự động xoá để tránh phình bộ nhớ.", "Unlimited items: recommended to enable auto-cleanup to save memory.")
                                     : tr("Không giới hạn số mục • tự động xoá sau \(clipboardManager.autoCleanupDays) ngày.", "Unlimited items • auto-cleans after \(clipboardManager.autoCleanupDays) days."))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                            }
                        }

                        // Ignore passwords toggle
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                            Text(tr("Tự động bỏ qua mật khẩu (1Password, Bitwarden, Keychain)", "Auto-ignore passwords (1Password, Bitwarden, Keychain)"))
                                .font(.system(size: FS.caption))
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
                                    .font(.system(size: FS.caption))
                                Text(tr("Mở bảng Clipboard HUD (\(clipboardManager.hudShortcut.displayTitle))", "Open Clipboard HUD (\(clipboardManager.hudShortcut.displayTitle))"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .cardBackground()

                // Screenshot (LightShot / ⌘⇧1) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: FS.body))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Chụp ảnh màn hình (⌘⇧1)", "Screenshot Snipping (⌘⇧1)"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(tr("Kéo chọn vùng, vẽ bút đỏ chú thích, ⌘C sao chép, ⌘S lưu tệp", "LightShot-style: crop area, red pen annotations, ⌘C copy, ⌘S save"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if screenshotManager.isScreenshotEnabled {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    screenshotManager.isDetailsExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: screenshotManager.isDetailsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(screenshotManager.isDetailsExpanded ? 0.08 : 0.04)))
                            }
                            .buttonStyle(.plain)
                            .help(screenshotManager.isDetailsExpanded ? tr("Thu gọn chi tiết", "Collapse details") : tr("Xem chi tiết cài đặt", "View settings details"))
                        }

                        Toggle("", isOn: Binding<Bool>(
                            get: { screenshotManager.isScreenshotEnabled },
                            set: { screenshotManager.isScreenshotEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if screenshotManager.isScreenshotEnabled && screenshotManager.isDetailsExpanded {
                        Divider().opacity(0.35)

                        // Shortcuts & Quick Actions Grid
                        ShortcutGrid {
                            shortcutPill(key: "⌘⇧1", desc: tr("Mở chụp ảnh", "Start Snipping"))
                            shortcutPill(key: "⌘C", desc: tr("Sao chép ảnh", "Copy Image"))
                            shortcutPill(key: "⌘S", desc: tr("Lưu ảnh PNG", "Save PNG"))
                            shortcutPill(key: "⎋", desc: tr("Huỷ bỏ", "Cancel"))
                        }

                        // Capture Now Button
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                screenshotManager.startCapture()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: FS.caption))
                                Text(tr("Chụp màn hình ngay (⌘⇧1)", "Capture Screenshot Now (⌘⇧1)"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .cardBackground()

                // Mouse Chording Card
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: FS.body))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Bấm đồng thời Chuột Trái + Phải mở F3", "Left + Right click opens Mission Control (F3)"))
                            .font(.system(size: FS.label, weight: .semibold))
                        Text(tr("Mở Mission Control ngay trên chuột mà không cần chạm bàn phím", "Trigger Mission Control directly from mouse without keyboard"))
                            .font(.system(size: FS.caption))
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
                .cardBackground()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func optionChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: FS.caption, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func shortcutPill(key: String, desc: String) -> some View {
        HStack(spacing: 6) {
            Text(desc)
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(key)
                .font(.system(size: FS.caption, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.07)))
        }
        .frame(maxWidth: .infinity)
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
                    .font(.system(size: FS.body))
                    .foregroundStyle(monitor.isConnected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.name)
                        .font(.system(size: FS.label, weight: .semibold))
                        .lineLimit(1)
                    Text("\(monitor.resolution) • \(monitor.isBuiltIn ? tr("Màn hình chính", "Built-in Display") : tr("Màn hình ngoài", "External Display"))")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(round(monitor.brightness * 100)))%")
                    .font(.system(size: FS.body, weight: .semibold, design: .rounded))
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
                        .font(.system(size: FS.caption, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.05)))
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Disconnect toggle
                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        Text(monitor.isBuiltIn ? tr("Tắt màn", "Turn Off") : tr("Ngắt mềm", "Disconnect"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
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
                        Text(tr("Đang ngắt mềm (Đã tắt)", "Disconnected (Turned Off)"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: FS.caption, weight: .semibold))
                            Text(tr("Bật lại", "Turn On"))
                                .font(.system(size: FS.caption, weight: .semibold))
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
            RoundedRectangle(cornerRadius: Rad.sm)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Rad.sm)
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
                            .font(.system(size: FS.caption))
                        Text(ext.isConnected ? tr("Ngắt màn ngoài", "Disconnect External") : tr("Bật màn ngoài", "Connect External"))
                            .font(.system(size: FS.caption, weight: ext.isConnected ? .regular : .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color(nsColor: .controlBackgroundColor)))
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
                            .font(.system(size: FS.caption))
                        Text(tr("Bật tất cả màn hình", "Turn On All Displays"))
                            .font(.system(size: FS.caption, weight: .semibold))
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
                .font(.system(size: FS.display))
                .foregroundStyle(.tertiary)
            Text(tr("Không tìm thấy màn hình nào", "No displays detected"))
                .font(.system(size: FS.label))
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
                            .font(.system(size: FS.hero, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.system(size: FS.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Live Wattage
                    if batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn {
                        Text("0.0W (" + tr("Nguồn AC trực tiếp", "Direct AC Power") + ")")
                            .font(.system(size: FS.label, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    } else if batteryManager.isCharging || (batteryManager.isPluggedIn && batteryManager.wattage > 0.05 && batteryManager.amperage > 0) {
                        Text(String(format: "+%.1fW (" + tr("Đang sạc", "Charging") + ")", batteryManager.wattage))
                            .font(.system(size: FS.label, weight: .semibold))
                            .foregroundStyle(Tone.good)
                    } else if batteryManager.isPluggedIn {
                        if batteryManager.isFullyCharged || batteryManager.currentLevel >= 100 {
                            Text(tr("Đã sạc đầy 100%", "Fully Charged"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(Tone.good)
                        } else if batteryManager.adapterWatts > 0 {
                            Text(String(format: "0.0W (" + tr("Củ sạc %dW", "Charger %dW") + ")", batteryManager.adapterWatts))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("0.0W (" + tr("Đã cắm sạc", "Plugged in") + ")")
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        let mins = batteryManager.timeRemaining
                        let timeStr = mins > 0 ? " • " + tr("Còn ~\(mins / 60)h\(mins % 60)m", "~\(mins / 60)h\(mins % 60)m left") : ""
                        Text(String(format: "-%.1fW%@", batteryManager.wattage, timeStr))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Custom Progress Bar with Lock Notch
                GeometryReader { geo in
                    let width = geo.size.width
                    let levelFraction = min(1.0, max(0.0, Double(batteryManager.currentLevel) / 100.0))
                    let limitFraction = min(1.0, max(0.0, Double(batteryManager.chargeLimit) / 100.0))

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Rad.sm)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: Rad.sm)
                            .fill(
                                LinearGradient(
                                    colors: (batteryManager.isProtectionEnabled && batteryManager.isBypassActive && batteryManager.isPluggedIn)
                                        ? [Color.accentColor, Color.accentColor]
                                        : [Tone.good, Color.accentColor],
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
                        Text(tr("Ngưỡng khóa: \(batteryManager.chargeLimit)%", "Charge limit: \(batteryManager.chargeLimit)%"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // 4 Hardware Health & Telemetry Metrics (Clean 4-column row)
            HStack(spacing: 5) {
                metricChip(
                    icon: "heart.fill",
                    iconColor: .secondary,
                    title: tr("Độ khỏe cell", "Cell Health"),
                    val: String(format: "%.1f%%", batteryManager.exactHealthPercent),
                    sub: "\(batteryManager.nominalCapacity)/\(batteryManager.designCapacity)"
                )
                metricChip(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .secondary,
                    title: tr("Chu kỳ sạc", "Cycle Count"),
                    val: "\(batteryManager.cycleCount) " + tr("lần", "cycles"),
                    sub: tr("Thiết kế: 1000", "Design: 1000")
                )
                Button {
                    onSelectThermalSection?()
                } label: {
                    metricChip(
                        icon: "thermometer.medium",
                        iconColor: tempBadgeColor,
                        title: tr("Nhiệt độ pin", "Battery Temp"),
                        val: String(format: "%.1f°C", batteryManager.temperature),
                        sub: tempStatusText + " ›",
                        valColor: tempBadgeColor
                    )
                }
                .buttonStyle(.plain)
                .help(tr("Bấm để mở kiểm soát nhiệt độ & quạt", "Click to open thermals & fans control"))

                metricChip(
                    icon: (batteryManager.isPluggedIn && batteryManager.adapterWatts > 0) ? "bolt.fill" : "battery.100",
                    iconColor: (batteryManager.isPluggedIn && batteryManager.adapterWatts > 0) ? .secondary : .secondary,
                    title: tr("Củ sạc", "Adapter"),
                    val: (batteryManager.isPluggedIn && batteryManager.adapterWatts > 0) ? "\(batteryManager.adapterWatts)W" : tr("Dùng Pin", "On Battery"),
                    sub: (batteryManager.isPluggedIn && batteryManager.adapterWatts > 0) ? (batteryManager.adapterDescription.isEmpty ? "USB-C PD" : batteryManager.adapterDescription) : tr("Không cắm sạc", "Unplugged")
                )
            }

            // High-Temperature Alert Banner
            if batteryManager.temperature >= batteryManager.tempAlertThreshold {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: FS.body)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Cảnh báo: Pin đang ấm (\(String(format: "%.1f°C", batteryManager.temperature)))!", "Warning: Battery is warm (\(String(format: "%.1f°C", batteryManager.temperature)))!"))
                            .font(.system(size: FS.caption, weight: .semibold)).foregroundStyle(.red)
                        Text(tr("MacBook Air không quạt. Hãy chuyển sang tab 'Đóng băng' để tạm dừng tiến trình nặng.", "Fanless MacBook. Switch to 'Freeze' tab to suspend heavy processes."))
                            .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.red.opacity(0.1)))
            }

            // Sub-Navigation Pills (4 Tabs: Nguồn SMC, Sleep Guard, Đóng băng CPU, Lịch hiệu chuẩn)
            HStack(spacing: 3) {
                subTabButton(index: 0, title: tr("Nguồn SMC", "SMC Power"), icon: "bolt.shield")
                subTabButton(index: 1, title: "Sleep Guard", icon: "moon.stars")
                subTabButton(index: 2, title: tr("Đóng băng", "Freeze"), icon: "snowflake")
                subTabButton(index: 3, title: tr("Hiệu chuẩn", "Calibrate"), icon: "calendar.badge.clock")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.05)))

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
        .cardBackground()
    }

    private func metricChip(icon: String, iconColor: Color, title: String, val: String, sub: String, valColor: Color = .primary) -> some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2.5) {
                Text(title).font(.system(size: FS.caption, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Text(val).font(.system(size: FS.body, weight: .semibold, design: .rounded)).foregroundStyle(valColor)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(sub).font(.system(size: FS.caption)).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
    }

    private func subTabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            batteryManager.selectedHardwareTab = index
            if index == 2 {
                energyManager.refreshProcesses()
            }
        } label: {
            HStack(spacing: 2.5) {
                Text(title).font(.system(size: FS.caption, weight: batteryManager.selectedHardwareTab == index ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Rad.sm))
            .background(
                RoundedRectangle(cornerRadius: Rad.sm)
                    .fill(batteryManager.selectedHardwareTab == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(batteryManager.selectedHardwareTab == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // SUB-TAB 0: NGUỒN SMC
    private var powerOverviewSubTab: some View {
        VStack(spacing: 7) {
            if !batteryManager.isHelperInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: FS.body))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        let isOldHelper = batteryManager.helperVersion > 0 && batteryManager.helperVersion < 2
                        Text(isOldHelper
                             ? tr("Cần cập nhật Helper SMC lên bản mới (v2)", "SMC Helper update required (v2)")
                             : tr("Chưa cấp quyền SMC (hoặc bạn đã bấm Bỏ qua)", "SMC Helper not installed (or skipped)"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(tr("Cần xác nhận Touch ID / Mật khẩu máy để khóa sạc 80% & chỉnh quạt", "Confirm with Touch ID / password to lock 80% & control fans"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        batteryManager.installHelper()
                    } label: {
                        HStack(spacing: 4) {
                            if batteryManager.isInstallingHelper {
                                ProgressView().controlSize(.mini)
                            }
                            let isOldHelper = batteryManager.helperVersion > 0 && batteryManager.helperVersion < 2
                            Text(batteryManager.isInstallingHelper
                                 ? tr("Đang cài...", "Installing...")
                                 : (isOldHelper ? tr("Cập nhật ngay", "Update Now") : tr("Cấp quyền ngay", "Grant Now")))
                                .font(.system(size: FS.caption, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(batteryManager.isInstallingHelper)
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.orange.opacity(0.08)))
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: FS.label))
                    .foregroundStyle(batteryManager.isProtectionEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Khóa sạc ở \(batteryManager.chargeLimit)% (Chạy điện trực tiếp)", "Charge limit at \(batteryManager.chargeLimit)% (Bypass Mode)"))
                        .font(.system(size: FS.label, weight: .semibold))
                    Text(tr("Cắm sạc liên tục không chai pin (SMC Bypass)", "Plug in continuously without battery wear (SMC Bypass)"))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isProtectionEnabled },
                    set: { newVal in
                        if newVal {
                            if !batteryManager.isHelperInstalled {
                                batteryManager.isProtectionEnabled = true
                                batteryManager.installHelper { success in
                                    if !success {
                                        batteryManager.isProtectionEnabled = false
                                    }
                                }
                            } else {
                                batteryManager.isProtectionEnabled = true
                            }
                        } else {
                            batteryManager.isProtectionEnabled = false
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isProtectionEnabled {
                HStack(spacing: 6) {
                    Text(tr("Mức khóa:", "Limit:"))
                        .font(.system(size: FS.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach([70, 80, 90], id: \.self) { val in
                        Button {
                            if val < 80 && !batteryManager.isHelperInstalled {
                                batteryManager.installHelper { success in
                                    if success {
                                        batteryManager.chargeLimit = val
                                    }
                                }
                            } else {
                                batteryManager.chargeLimit = val
                            }
                        } label: {
                            Text("\(val)%\(val == 80 ? " (" + tr("Chuẩn", "Standard") + ")" : "")")
                                .font(.system(size: FS.caption, weight: batteryManager.chargeLimit == val ? .semibold : .medium))
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
                            .font(.system(size: FS.caption))
                        Text(batteryManager.isTopUpActive ? tr("Hủy sạc 100% (Khóa lại)", "Cancel 100% (Re-lock)") : tr("Sạc đầy 100% tạm thời", "Temporary 100% Top-up"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(batteryManager.isTopUpActive ? Color.orange.opacity(0.10) : Color.primary.opacity(0.06))
                    .foregroundStyle(batteryManager.isTopUpActive ? Color.orange : Color.primary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(tr("Khi cần mang máy ra ngoài", "When taking laptop on the go")).font(.system(size: FS.caption)).foregroundStyle(.tertiary)
                    .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(-1)
            }

            // Toggles
            toggleRow(icon: "thermometer.sun.fill", iconColor: .secondary, title: tr("Thông báo khi pin nóng > 38°C", "Alert when battery temp > 38°C"), isOn: Binding<Bool>(
                get: { batteryManager.isTempAlertEnabled },
                set: { batteryManager.isTempAlertEnabled = $0 }
            ))
            toggleRow(icon: "bell.badge.fill", iconColor: .secondary, title: tr("Cảnh báo chống chai pin (Màn ngoài, pin < 20%)", "Battery health warning (External display, < 20%)"), isOn: Binding<Bool>(
                get: { batteryManager.isSmartAlertsEnabled },
                set: { batteryManager.isSmartAlertsEnabled = $0 }
            ))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: FS.label))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(tr("Lưu ý: Tắt 'Sạc pin tối ưu hoá' trong Cài đặt hệ thống để tránh macOS tự sạc lên 100%.", "Tip: Turn off 'Optimized Battery Charging' in macOS Settings to prevent macOS overriding limit."))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    // SUB-TAB 1: SLEEP GUARD
    private var sleepGuardSubTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "moon").font(.system(size: FS.label)).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Bảo vệ Sleep Guard khi gập máy", "Sleep Guard Clamshell Protection"))
                        .font(.system(size: FS.label, weight: .semibold))
                    Text(tr("Chống Dark Wake và ngăn máy nóng ngầm trong balo", "Prevents Dark Wake & background heating in backpack"))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
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
                    Image(systemName: "wave.3.forward").font(.system(size: FS.label)).foregroundStyle(.secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Tự ngắt Bluetooth khi gập máy", "Auto-disconnect Bluetooth on lid close"))
                            .font(.system(size: FS.label, weight: .semibold))
                        Text(tr("AirPods/chuột không đánh thức máy ngầm qua đêm. Tự bật lại ngay khi mở máy.", "AirPods/mouse won't wake Mac overnight. Auto re-connects on lid open."))
                            .font(.system(size: FS.caption)).foregroundStyle(.secondary)
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

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: FS.label)).foregroundStyle(.secondary).frame(width: 16)
                    Text(tr("Khóa SMC 80% được bảo lưu liên tục trong lúc ngủ và tái kích hoạt ngay khi mở màn hình.", "SMC 80% limit is preserved during sleep and reapplied on wake."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                }

                if !batteryManager.lastSleepReport.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: FS.label)).foregroundStyle(.secondary).frame(width: 16)
                        Text(tr("Lần gần nhất: \(batteryManager.lastSleepReport)", "Last report: \(batteryManager.lastSleepReport)"))
                            .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // SUB-TAB 2: PROCESS FREEZE
    private var processFreezeSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("Tiến trình ngốn CPU & Tỏa nhiệt:", "Heavy CPU & Heat Generating Processes:"))
                    .font(.system(size: FS.caption, weight: .semibold))
                Spacer()
                Button {
                    energyManager.refreshProcesses()
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: FS.caption))
                        Text(tr("Quét lại", "Refresh")).font(.system(size: FS.caption))
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
                    Text(tr("Máy đang rất mát mẻ, không có tiến trình nền nặng.", "System is running cool, no heavy background processes."))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 3.5) {
                    ForEach(energyManager.processes) { p in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(p.isFrozen ? Color.accentColor : (p.cpu > 25.0 ? Color.red : Color.orange))
                                .frame(width: 5, height: 5)

                            VStack(alignment: .leading, spacing: 0.5) {
                                Text(p.name)
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .lineLimit(1)
                                Text("PID: \(p.pid)")
                                    .font(.system(size: FS.caption)).foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if p.isFrozen {
                                Text("❄️ " + tr("ĐÃ ĐÓNG BĂNG", "FROZEN"))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            } else {
                                Text(String(format: "%.1f%% CPU", p.cpu))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .foregroundStyle(p.cpu > 25.0 ? Color.red : Color.orange)
                            }

                            Button {
                                if p.isFrozen {
                                    energyManager.resumeProcess(pid: p.pid)
                                } else {
                                    energyManager.freezeProcess(pid: p.pid)
                                }
                            } label: {
                                Text(p.isFrozen ? ("▶️ " + tr("Rã đông", "Resume")) : ("❄️ " + tr("Đóng băng", "Freeze")))
                                    .font(.system(size: FS.caption, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(p.isFrozen ? Tone.good.opacity(0.10) : Color.accentColor.opacity(0.10))
                                    .foregroundStyle(p.isFrozen ? Tone.good : Color.accentColor)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))
                    }
                }
            }

            Text(tr("Đóng băng (SIGSTOP) giữ nguyên cửa sổ và dữ liệu trong RAM nhưng ngừng 100% việc đốt CPU và tỏa nhiệt trên M2.", "Freezing (SIGSTOP) keeps windows & data in RAM while completely halting CPU burn & heat."))
                .font(.system(size: FS.caption)).foregroundStyle(.secondary)
        }
    }

    // SUB-TAB 3: AUTO-SCHEDULED BATTERY CALIBRATION (BMS)
    private var autoScheduledCalibrationSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Master Auto-Schedule Toggle
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: FS.body))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Tự động đặt lịch hiệu chuẩn pin định kỳ", "Auto-schedule Periodic Battery Calibration"))
                        .font(.system(size: FS.label, weight: .semibold))
                    Text(tr("Cân bằng điện áp cell & khôi phục thước đo dung lượng chuẩn", "Balances cell voltage & recalibrates gauge"))
                        .font(.system(size: FS.caption))
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
                    Text(tr("Chu kỳ:", "Interval:"))
                        .font(.system(size: FS.caption, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach([30, 45, 60], id: \.self) { days in
                        Button {
                            batteryManager.calibrationIntervalDays = days
                        } label: {
                            Text(tr("\(days) ngày", "\(days) days") + (days == 30 ? " ★" : ""))
                                .font(.system(size: FS.caption, weight: batteryManager.calibrationIntervalDays == days ? .semibold : .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(batteryManager.calibrationIntervalDays == days ? Color.accentColor : Color.primary.opacity(0.06))
                                .foregroundStyle(batteryManager.calibrationIntervalDays == days ? Color.white : Color.primary)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                // Schedule Info Box
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        Text(tr("Lịch tiếp theo:", "Next date:"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(formatDate(batteryManager.nextScheduledCalibrationDate))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(tr("Còn \(batteryManager.daysRemainingUntilCalibration) ngày", "\(batteryManager.daysRemainingUntilCalibration) days left"))
                            .font(.system(size: FS.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }

                    HStack {
                        Image(systemName: "checkmark.circle").font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        Text(tr("Lần gần nhất:", "Last completed:"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(batteryManager.lastCalibrationDate != nil ? formatDate(batteryManager.lastCalibrationDate!) : tr("Chưa thực hiện", "Never performed"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Text(tr("Quy trình: Khi đến lịch, bạn rút sạc dùng máy tự nhiên xuống ≤ 20%. Khi cắm sạc lại, HyperMac sẽ tự động sạc 100% cân bằng cell ➔ ngâm 15p ➔ tự khóa lại 80% SMC Bypass.", "Procedure: When due, unplug & use normally down to ≤ 20%. Once plugged back in, HyperMac charges to 100% to balance cells ➔ soaks for 15m ➔ re-locks to 80% SMC Bypass."))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))
            }

            // Action: Manual Run or Active Status
            if batteryManager.calibrationState == .idle {
                Button {
                    batteryManager.startCalibration()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle.fill").font(.system(size: FS.caption))
                        Text(tr("Hiệu chuẩn ngay bây giờ (Chạy trước lịch)", "Calibrate now (Run ahead of schedule)"))
                            .font(.system(size: FS.caption, weight: .semibold))
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
                            .font(.system(size: FS.caption, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.orange.opacity(0.1)))

                    Button {
                        batteryManager.cancelCalibration()
                    } label: {
                        Text(tr("Hủy hiệu chuẩn (Quay về khóa 80%)", "Cancel calibration (Revert to 80% lock)"))
                            .font(.system(size: FS.caption, weight: .semibold))
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: FS.label))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(title)
                .font(.system(size: FS.label))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
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
            return Tone.good
        } else if batteryManager.temperature < 38.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var tempStatusText: String {
        if batteryManager.temperature < 32.0 {
            return tr("Mát mẻ", "Cool")
        } else if batteryManager.temperature < 38.0 {
            return tr("Ấm nhẹ", "Warm")
        } else {
            return tr("Nóng!", "Hot!")
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

            // 1b. Fan control (hidden on fanless Macs)
            FanControlCardView(fan: FanManager.shared)

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
                        .font(.system(size: FS.subhead, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(thermalManager.machineModelName)
                            .font(.system(size: FS.body, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("HID PMU")
                            .font(.system(size: FS.caption, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }

                    Text(tr("Cảm biến nhiệt Apple Silicon • Cập nhật mỗi 2.5s", "Apple Silicon Thermal Sensors • Updates every 2.5s"))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Thermal State Pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 5, height: 5)
                    Text(localizedThermalStateDescription)
                        .font(.system(size: FS.caption, weight: .semibold))
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
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(thermalManager.isRefreshing ? 360 : 0))
                        .animation(thermalManager.isRefreshing ? .linear(duration: 0.4) : .default, value: thermalManager.isRefreshing)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help(tr("Làm mới cảm biến nhiệt ngay lập tức", "Refresh thermal sensors immediately"))
            }
        }
        .padding(8)
        .cardBackground()
    }

    // MARK: - 2. Menu Bar Monitor (temperature only)

    private var menuBarMonitorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.dock.rectangle")
                .font(.system(size: FS.caption))
                .foregroundStyle(Color.accentColor)

            Text(tr("Hiện nhiệt độ trên Menu Bar", "Show temperature on Menu Bar"))
                .font(.system(size: FS.caption))
                .foregroundStyle(.secondary)

            Spacer()

            if thermalManager.showMenuBarMetrics {
                Text("\(Int(thermalManager.cpuAvgTemp))°C")
                    .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            Toggle("", isOn: Binding<Bool>(
                get: { thermalManager.showMenuBarMetrics },
                set: { thermalManager.showMenuBarMetrics = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(8)
        .cardBackground()
    }

    // MARK: - 3. Apple Silicon Thermal Matrix (6 Core Metrics)
    private var thermalMatrixGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(tr("Bản đồ nhiệt Apple Silicon (HID PMU)", "Apple Silicon Thermal Matrix (HID PMU)"), systemImage: "cpu")
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(tr("Thời gian thực: 2.5s", "Real-time: 2.5s"))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                sensorTile(
                    title: tr("CPU Trung bình", "CPU Average"),
                    temp: thermalManager.cpuAvgTemp,
                    icon: "cpu",
                    sub: tr("Tất cả các nhân", "All Cores Average")
                )
                sensorTile(
                    title: tr("CPU Nóng nhất", "CPU Peak"),
                    temp: thermalManager.cpuPeakTemp,
                    icon: "flame.fill",
                    sub: "Core Peak Hotspot"
                )
                sensorTile(
                    title: tr("GPU Đồ họa", "GPU Core"),
                    temp: thermalManager.gpuAvgTemp,
                    icon: "gamecontroller.fill",
                    sub: tr("Cụm nhân GPU", "GPU Cluster")
                )
                sensorTile(
                    title: tr("Pin Cell", "Battery Pack"),
                    temp: thermalManager.batteryTemp,
                    icon: "battery.100.bolt",
                    sub: "Gas Gauge Pack"
                )
                sensorTile(
                    title: tr("Ổ cứng SSD", "SSD Storage"),
                    temp: thermalManager.ssdTemp,
                    icon: "internaldrive.fill",
                    sub: "NAND Flash Storage"
                )
                sensorTile(
                    title: tr("Hotspot Bo mạch", "Motherboard Hotspot"),
                    temp: thermalManager.hotspotTemp,
                    icon: "thermometer.sun.fill",
                    sub: "PMU Calibration"
                )
            }
        }
        .padding(8)
        .cardBackground()
    }

    private func sensorTile(title: String, temp: Double, icon: String, sub: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: FS.body))
                .foregroundStyle(tempColor(temp))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: FS.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(temp > 0 ? String(format: "%.1f°C", temp) : "—")
                    .font(.system(size: FS.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor(temp))

                Text(sub)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))
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
                        .font(.system(size: FS.caption))
                        .foregroundStyle(Color.accentColor)

                    Text(tr("Chi tiết \(thermalManager.detailedSensors.count) cảm biến PMU trên chip", "Detailed \(thermalManager.detailedSensors.count) on-chip PMU sensors"))
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: thermalManager.isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            if thermalManager.isDetailExpanded {
                VStack(spacing: 3) {
                    ForEach(thermalManager.detailedSensors) { s in
                        HStack {
                            Text(s.displayName)
                                .font(.system(size: FS.caption, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("(\(s.name))")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(String(format: "%.1f°C", s.temp))
                                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                                .foregroundStyle(tempColor(s.temp))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.02)))
            }
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        guard temp > 0 else { return .secondary }
        if temp < 55.0 {
            return Tone.good
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
            return Tone.good
        } else if peak < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var localizedThermalStateDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return tr("Mát mẻ (Bình thường)", "Nominal (Cool)")
        case .fair: return tr("Ấm nhẹ (Tải vừa)", "Fair (Moderate)")
        case .serious: return tr("Nóng (Đang giảm xung)", "Serious (Throttling)")
        case .critical: return tr("Rất nóng (Throttling tối đa!)", "Critical (Heavy Throttling!)")
        @unknown default: return tr("Bình thường", "Normal")
        }
    }

    private var headerIconColor: Color {
        Color.accentColor
    }

    private var headerIconBackground: Color {
        Color.accentColor.opacity(0.12)
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                Text(tr("Open Source • Miễn phí", "Open Source • Free"))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Author Link Button
            Button {
                if let url = URL(string: "https://bit.ly/4ectK8U") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: FS.caption))
                    Text(tr("Tác giả", "Author"))
                        .font(.system(size: FS.caption, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help(tr("Xem trang tác giả", "View author profile"))

            // Update Check / Action Button
            if !UpdateManager.updatesDisabled {
                Button {
                    updateManager.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: updateManager.hasNewUpdate ? "sparkles" : "arrow.triangle.2.circlepath")
                            .font(.system(size: FS.caption))
                        let cleanVer = updateManager.latestVersionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                        Text(updateManager.hasNewUpdate ? tr("Có bản v\(cleanVer)", "New v\(cleanVer)") : tr("Cập nhật", "Updates"))
                            .font(.system(size: FS.caption, weight: updateManager.hasNewUpdate ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(updateManager.hasNewUpdate ? Tone.good.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(updateManager.hasNewUpdate ? Tone.good : Color.primary)
                }
                .buttonStyle(.plain)
                .help(updateManager.hasNewUpdate ? tr("Đã có bản mới! Bấm để cập nhật", "New version available! Click to update") : tr("Kiểm tra phiên bản mới từ GitHub", "Check for newer version on GitHub"))
            }

            // Donate Button
            Button {
                updateManager.showDonateModal = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                    Text("Donate")
                        .font(.system(size: FS.caption, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help(tr("Ủng hộ tác giả phát triển phần mềm", "Support the author"))
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
                            .font(.system(size: FS.value, weight: .bold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("Cập nhật HyperMac", "Update HyperMac"))
                                .font(.system(size: FS.body, weight: .semibold))
                            Text(tr("Phiên bản hiện tại: v\(UpdateManager.currentVersion)", "Current version: v\(UpdateManager.currentVersion)"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        updateManager.showUpdateModal = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: FS.subhead))
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
                        Text(tr("Đang kiểm tra bản cập nhật mới trên GitHub...", "Checking for updates on GitHub..."))
                            .font(.system(size: FS.label))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .upToDate(let ver):
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: FS.huge))
                            .foregroundStyle(.secondary)

                        Text(tr("Bạn đang dùng phiên bản mới nhất!", "You are using the latest version!"))
                            .font(.system(size: FS.body, weight: .semibold))

                        Text(tr("HyperMac v\(ver) hiện là phiên bản cập nhật nhất. Máy của bạn đã sẵn sàng.", "HyperMac v\(ver) is currently the newest release. You are all set."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        Button {
                            updateManager.checkForUpdates(silent: false)
                        } label: {
                            Text(tr("Kiểm tra lại", "Check Again"))
                                .font(.system(size: FS.label, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .updateAvailable(let ver, let notes, _, _):
                    let displayVer = ver.hasPrefix("v") || ver.hasPrefix("V") ? ver : "v\(ver)"
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: FS.subhead))
                                .foregroundStyle(.secondary)

                            Text(tr("Đã có phiên bản mới: \(displayVer)", "New version available: \(displayVer)"))
                                .font(.system(size: FS.body, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        // Release Notes Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Điểm mới trong bản \(displayVer):", "What's new in \(displayVer):"))
                                .font(.system(size: FS.caption, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.vertical, showsIndicators: true) {
                                Text(notes)
                                    .font(.system(size: FS.caption))
                                    .lineSpacing(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(height: 95)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm)
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
                                        .font(.system(size: FS.body, weight: .semibold))
                                    Text(tr("Cập nhật ngay (Tự động tải & Cài đặt)", "Update Now (Auto Download & Install)"))
                                        .font(.system(size: FS.label, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: Rad.sm)
                                        .fill(Color.accentColor)
                                )
                                .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text(tr("Xem chi tiết trên GitHub", "View details on GitHub"))
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                case .downloading(let progress):
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: FS.hero))
                            .foregroundStyle(Color.accentColor)

                        Text(tr("Đang tải bản cập nhật: \(Int(progress * 100))%", "Downloading update: \(Int(progress * 100))%"))
                            .font(.system(size: FS.body, weight: .semibold))

                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 20)

                        Text(tr("HyperMac sẽ tự động thay thế và khởi động lại ngay sau khi tải xong.", "HyperMac will automatically replace the old version and restart once complete."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .extracting, .readyToRestart:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)

                        Text(tr("Đang cài đặt & chuẩn bị khởi động lại...", "Installing & preparing to restart..."))
                            .font(.system(size: FS.body, weight: .semibold))

                        Text(tr("Ứng dụng sẽ tự động mở lại trong giây lát.", "The application will reopen automatically in a moment."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .failed(let errorMsg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: FS.hero))
                            .foregroundStyle(.orange)

                        Text(tr("Không thể cập nhật tự động", "Failed to update automatically"))
                            .font(.system(size: FS.body, weight: .semibold))

                        Text(errorMsg)
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        HStack(spacing: 8) {
                            Button {
                                updateManager.checkForUpdates(silent: false)
                            } label: {
                                Text(tr("Thử lại", "Try Again"))
                                    .font(.system(size: FS.caption, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text(tr("Mở GitHub Releases", "Open GitHub Releases"))
                                    .font(.system(size: FS.caption, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.10)))
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
                    Text(tr("Tự động kiểm tra bản mới khi mở HyperMac", "Automatically check for updates on startup"))
                        .font(.system(size: FS.caption))
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
                RoundedRectangle(cornerRadius: Rad.md)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Rad.md)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Donate Modal View

private func getDonateQRImage() -> NSImage? {
    if let path = Bundle.main.path(forResource: "donate_qr", ofType: "jpg"),
       let img = NSImage(contentsOfFile: path) {
        return img
    }
    let fallbackPaths = [
        "/Applications/HyperMac.app/Contents/Resources/donate_qr.jpg",
        FileManager.default.currentDirectoryPath + "/Resources/donate_qr.jpg",
        "/Users/khacdai24/.gemini/antigravity/brain/94879281-6fae-438e-aee5-006283e6be3d/.user_uploaded/media_1793609797893_7b196951.jpg"
    ]
    for p in fallbackPaths {
        if FileManager.default.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) {
            return img
        }
    }
    return nil
}

struct DonateModalView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        ZStack {
            // Dimmed semi-transparent backdrop
            Color.black.opacity(0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    updateManager.showDonateModal = false
                }

            // Modal Dialog Card
            VStack(spacing: 8) {
                // Header Bar
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: FS.value, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("Ủng hộ tác giả (Donate)", "Support Author (Donate)"))
                                .font(.system(size: FS.body, weight: .semibold))
                            Text(tr("Tiếp thêm động lực phát triển HyperMac", "Fuel HyperMac's continuous development"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        updateManager.showDonateModal = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: FS.title))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Đóng", "Close"))
                }

                Divider()

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        // QR Code Image
                        if let qrImg = getDonateQRImage() {
                            VStack(spacing: 4) {
                                Image(nsImage: qrImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 205, maxHeight: 255)
                                    .clipShape(RoundedRectangle(cornerRadius: Rad.md, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.2)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 3)

                                Text(tr("Quét mã bằng mọi app ngân hàng", "Scan QR with any banking app"))
                                    .font(.system(size: FS.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 1)
                        }

                        // Message Box
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr(
                                "Thật sự cảm ơn bạn đã nhấn vào nút này, từ tận đáy lòng, mình luôn trân trọng số tiền mọi người ủng hộ kể cả ít hay nhiều, điều đó cho mình một động lực rất lớn để tiếp tục phát triển phần mềm này.",
                                "Thank you so much for clicking this button. From the bottom of my heart, I truly appreciate any contribution, big or small. It gives me great motivation to keep maintaining and improving this app."
                            ))
                                .font(.system(size: FS.label))
                                .lineSpacing(2.5)
                                .foregroundStyle(.primary.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(tr(
                                "Mình xin chân thành cảm ơn tấm lòng của mọi người 😊😊😊.",
                                "I sincerely thank each and every one of you for your support 😊😊😊."
                            ))
                                .font(.system(size: FS.label, weight: .semibold))
                                .lineSpacing(2.5)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(tr(
                                "Nếu được, rất mong bạn có thể nhắn cho mình thông tin donate qua FB để mình có thể gửi lời cảm ơn trực tiếp đến bạn ❤️",
                                "If possible, please send me a quick message on Facebook so I can thank you personally ❤️"
                            ))
                                .font(.system(size: FS.label))
                                .lineSpacing(2.5)
                                .foregroundStyle(.primary.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                                .fill(Color.accentColor.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.10), lineWidth: 1)
                        )

                        // Facebook Link Button
                        Button {
                            if let url = URL(string: "https://bit.ly/4ectK8U") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: FS.label))
                                Text(tr("Nhắn tin qua Facebook cho tác giả ↗", "Message author on Facebook ↗"))
                                    .font(.system(size: FS.label, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 515)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Rad.md)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Rad.md)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Community Activation Modal (Zalo Group Onboarding)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct ActivationModalView: View {
    @ObservedObject var activationManager: ActivationManager
    private let zaloBlue = Color(red: 0.0, green: 0.41, blue: 1.0)

    var body: some View {
        ZStack {
            // High-contrast dimmed backdrop preventing accidental bypass
            Color.black.opacity(0.65)
                .edgesIgnoringSafeArea(.all)

            // Main Activation Dialog Card
            VStack(spacing: 0) {
                // Header Bar
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: FS.subhead, weight: .bold))
                        .foregroundStyle(zaloBlue)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(zaloBlue.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(tr("Kích hoạt HyperMac", "Activate HyperMac"))
                                .font(.system(size: FS.title, weight: .bold))
                            Text(tr("MIỄN PHÍ", "FREE"))
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Tone.good.opacity(0.16)))
                                .foregroundStyle(Tone.good)
                        }
                        Text(tr("Tham gia cộng đồng Zalo để nhận mã vĩnh viễn", "Join our Zalo group to receive the lifetime key"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                // Scrollable Body
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 11) {
                        // Instruction Notice Card
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tr("Hướng dẫn nhận mã:", "How to get your key:"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(tr(
                                "1. Nhấn nút bên dưới để tham gia nhóm Zalo HyperMac.\n2. Xem tin nhắn đã ghim ở đầu nhóm để lấy mã kích hoạt.\n3. Nhập mã vào ô bên dưới và bấm Kích hoạt.",
                                "1. Tap the button below to join the HyperMac Zalo group.\n2. Check the pinned message at the top of the group for the key.\n3. Enter the key below and click Activate."
                            ))
                            .font(.system(size: FS.label))
                            .lineSpacing(2.5)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )

                        // Primary Zalo Group Button
                        Button {
                            activationManager.openZaloGroup()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: FS.body))
                                Text(tr("Tham gia nhóm Zalo lấy Key ↗", "Join Zalo Group for Key ↗"))
                                    .font(.system(size: FS.body, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                    .fill(zaloBlue)
                            )
                            .foregroundStyle(Color.white)
                            .shadow(color: zaloBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help(tr("Mở liên kết nhóm Zalo trong trình duyệt", "Open Zalo group link in browser"))

                        // QR Code Scanner Box
                        if let qrImg = activationManager.getZaloQRImage() {
                            VStack(spacing: 5) {
                                Image(nsImage: qrImg)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 140, height: 140)
                                    .padding(6)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: Rad.sm, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)

                                Text(tr("Hoặc quét mã QR bằng Zalo trên điện thoại", "Or scan this QR code with Zalo on your phone"))
                                    .font(.system(size: FS.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        // Key Input & Submit Box
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Nhập mã kích hoạt:", "Enter Activation Key:"))
                                .font(.system(size: FS.label, weight: .semibold))
                                .foregroundStyle(.primary)

                            HStack(spacing: 8) {
                                TextField(tr("Nhập mã từ tin nhắn ghim...", "Enter key from pinned message..."), text: $activationManager.inputKey, onCommit: {
                                    activationManager.submitKey()
                                })
                                .textFieldStyle(.plain)
                                .font(.system(size: FS.body, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                        .stroke(activationManager.errorMessage != nil ? Tone.bad : Color.primary.opacity(0.15), lineWidth: 1)
                                )

                                Button {
                                    activationManager.submitKey()
                                } label: {
                                    HStack(spacing: 4) {
                                        if activationManager.isSuccess {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: FS.label, weight: .bold))
                                        }
                                        Text(activationManager.isSuccess ? tr("Đã xong", "Done") : tr("Kích hoạt", "Activate"))
                                            .font(.system(size: FS.label, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                            .fill(activationManager.isSuccess ? Tone.good : Tone.accent)
                                    )
                                    .foregroundStyle(Color.white)
                                }
                                .buttonStyle(.plain)
                                .disabled(activationManager.inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            // Error or Success Feedback
                            if let err = activationManager.errorMessage {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: FS.caption))
                                    Text(err)
                                        .font(.system(size: FS.caption))
                                }
                                .foregroundStyle(Tone.bad)
                                .padding(.top, 1)
                            } else if activationManager.isSuccess {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: FS.caption))
                                    Text(tr("Kích hoạt thành công! Chúc bạn trải nghiệm tuyệt vời.", "Successfully activated! Enjoy HyperMac."))
                                        .font(.system(size: FS.caption, weight: .medium))
                                }
                                .foregroundStyle(Tone.good)
                                .padding(.top, 1)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )

                        // Lifetime Guarantee Note
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(Tone.good)
                                .padding(.top, 1)

                            Text(tr(
                                "Chỉ cần nhập 1 lần duy nhất. Trạng thái kích hoạt được lưu vĩnh viễn trên máy và không bao giờ hỏi lại kể cả sau khi cập nhật phiên bản mới.",
                                "You only need to activate once. Lifetime access is preserved permanently on this Mac across future updates."
                            ))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 490)
            }
            .background(
                RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 14)
        }
    }
}
