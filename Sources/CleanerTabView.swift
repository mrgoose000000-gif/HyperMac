import SwiftUI
import AppKit

// MARK: - Tab 3: System Cleaner & App Uninstaller (CleanMyMac Replacement)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
public struct CleanerTabView: View {
    @ObservedObject var cleanerManager: SystemCleanerManager

    public init(cleanerManager: SystemCleanerManager) {
        self.cleanerManager = cleanerManager
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Sub-Segment Navigation Bar
            subTabBar

            // Sub-Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    switch cleanerManager.selectedSection {
                    case 1:
                        appUninstallerSection
                    case 2:
                        largeFilesSection
                    default:
                        systemJunkSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            if cleanerManager.totalJunkBytes == 0 && !cleanerManager.isScanningJunk {
                cleanerManager.scanJunk()
            }
        }
    }

    // MARK: - Sub Tab Bar

    private var subTabBar: some View {
        HStack(spacing: 4) {
            subTabButton(index: 0, title: tr("Dọn rác", "Junk"), icon: "sparkles")
            subTabButton(index: 1, title: tr("Gỡ App", "Uninstaller"), icon: "trash")
            subTabButton(index: 2, title: tr("Tệp lớn", "Large Files"), icon: "doc.badge.gearshape")
        }
        .padding(2.5)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func subTabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                cleanerManager.selectedSection = index
            }
            if index == 1 && cleanerManager.installedApps.isEmpty && !cleanerManager.isScanningApps {
                cleanerManager.scanInstalledApps()
            }
            if index == 2 && cleanerManager.largeFiles.isEmpty && !cleanerManager.isScanningLargeFiles {
                cleanerManager.scanLargeFiles()
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: FS.caption, weight: cleanerManager.selectedSection == index ? .semibold : .medium))
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Rad.sm))
            .background(
                RoundedRectangle(cornerRadius: Rad.sm)
                    .fill(cleanerManager.selectedSection == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(cleanerManager.selectedSection == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - SECTION 0: SYSTEM JUNK CLEANER

    private var systemJunkSection: some View {
        VStack(spacing: 10) {
            // Hero Status Card
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 40, height: 40)

                        Image(systemName: cleanerManager.totalJunkBytes > 0 ? "trash.circle.fill" : "checkmark.seal.fill")
                            .font(.system(size: FS.display, weight: .bold))
                            .foregroundStyle(cleanerManager.totalJunkBytes > 0 ? Color.accentColor : Tone.good)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanerManager.isScanningJunk ? tr("Đang quét hệ thống...", "Scanning system...") : (cleanerManager.totalJunkBytes > 0 ? SystemCleanerManager.formatBytes(cleanerManager.totalJunkBytes) : tr("Hệ thống sạch sẽ", "System is Clean")))
                            .font(.system(size: FS.value, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(cleanerManager.isScanningJunk ? tr("Đang kiểm tra Caches, Logs & Trash...", "Checking Caches, Logs & Trash...") : tr("Dung lượng rác có thể giải phóng ngay", "Junk space ready to be freed"))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if cleanerManager.isScanningJunk || cleanerManager.isCleaningJunk {
                        ProgressView().controlSize(.small)
                    }
                }

                // Action Buttons
                HStack(spacing: 8) {
                    Button {
                        cleanerManager.cleanSelectedJunk()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: FS.caption, weight: .semibold))
                            Text(cleanerManager.isCleaningJunk ? tr("Đang dọn sạch...", "Cleaning...") : tr("Dọn sạch ngay", "Clean Now"))
                                .font(.system(size: FS.caption, weight: .semibold))
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(cleanerManager.totalJunkBytes > 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundStyle(Color.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(cleanerManager.totalJunkBytes == 0 || cleanerManager.isCleaningJunk || cleanerManager.isScanningJunk)

                    Button {
                        cleanerManager.scanJunk()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: FS.caption, weight: .semibold))
                            Text(tr("Quét lại", "Rescan"))
                                .font(.system(size: FS.caption, weight: .semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.06))
                        .foregroundStyle(.primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(cleanerManager.isScanningJunk || cleanerManager.isCleaningJunk)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color(nsColor: .controlBackgroundColor)))

            // Success feedback message
            if let msg = cleanerManager.cleanedMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: FS.label))
                    Text(msg)
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(Tone.good)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Tone.good.opacity(0.12)))
                .transition(.opacity)
            }

            // Categories Checklist
            VStack(spacing: 6) {
                ForEach(cleanerManager.junkCategories.indices, id: \.self) { idx in
                    junkCategoryCard(index: idx)
                }
            }
        }
    }

    private func junkCategoryCard(index: Int) -> some View {
        let cat = cleanerManager.junkCategories[index]
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Rad.sm)
                    .fill(cat.iconColor.opacity(0.15))
                    .frame(width: 26, height: 26)

                Image(systemName: cat.icon)
                    .font(.system(size: FS.body, weight: .semibold))
                    .foregroundStyle(cat.iconColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(cat.localizedTitle)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(cat.localizedSubtitle)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(cat.sizeFormatted)
                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cat.sizeBytes > 0 ? Color.primary : Color.secondary)

            Toggle("", isOn: Binding<Bool>(
                get: { cleanerManager.junkCategories[index].isSelected },
                set: { cleanerManager.junkCategories[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(cat.sizeBytes == 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - SECTION 1: APP UNINSTALLER

    private var appUninstallerSection: some View {
        VStack(spacing: 8) {
            // Search & Scan Bar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)

                    TextField(tr("Tìm ứng dụng cần gỡ...", "Search apps to uninstall..."), text: Binding<String>(
                        get: { cleanerManager.appSearchQuery },
                        set: { cleanerManager.appSearchQuery = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: FS.caption))

                    if !cleanerManager.appSearchQuery.isEmpty {
                        Button {
                            cleanerManager.appSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))

                Button {
                    cleanerManager.scanInstalledApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(tr("Quét lại danh sách ứng dụng", "Rescan application list"))
            }

            // Uninstall Result Alert
            if let msg = cleanerManager.uninstallMessage {
                let isWarning = msg.contains("")
                HStack(spacing: 6) {
                    Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isWarning ? .orange : Tone.good)
                        .font(.system(size: FS.label))
                    Text(msg)
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(isWarning ? .orange : Tone.good)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill((isWarning ? Color.orange : Tone.good).opacity(0.12)))
            }

            // Selected App Leftovers Inspector
            if let selected = cleanerManager.selectedApp {
                selectedAppDetailCard(app: selected)
            } else {
                // Apps List
                let filtered = cleanerManager.installedApps.filter {
                    cleanerManager.appSearchQuery.isEmpty ||
                    $0.name.localizedCaseInsensitiveContains(cleanerManager.appSearchQuery) ||
                    $0.bundleID.localizedCaseInsensitiveContains(cleanerManager.appSearchQuery)
                }

                if cleanerManager.isScanningApps {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(tr("Đang quét danh sách ứng dụng trong /Applications...", "Scanning apps in /Applications..."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else if filtered.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: FS.display))
                            .foregroundStyle(.secondary)
                        Text(tr("Không tìm thấy ứng dụng nào.", "No applications found."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 4) {
                        HStack {
                            Text(tr("\(filtered.count) ứng dụng", "\(filtered.count) applications"))
                                .font(.system(size: FS.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(tr("Bấm vào để xem & gỡ sạch file rác", "Click to inspect & clean leftovers"))
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(filtered) { app in
                            appRowCard(app: app)
                        }
                    }
                }
            }
        }
    }

    private func appRowCard(app: InstalledAppItem) -> some View {
        Button {
            cleanerManager.inspectAppLeftovers(for: app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(SystemCleanerManager.formatBytes(app.appSizeBytes))
                    .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color(nsColor: .controlBackgroundColor)))
        }
        .buttonStyle(.plain)
    }

    private func selectedAppDetailCard(app: InstalledAppItem) -> some View {
        VStack(spacing: 8) {
            // Header with back button
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: FS.body, weight: .semibold))
                    Text(app.bundleID)
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    cleanerManager.selectedApp = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: FS.subhead))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))

            // Leftovers list
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tr("Các tệp sẽ được chuyển vào Thùng rác:", "Files that will be moved to Trash:"))
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tr("Tổng cộng: \(app.totalSizeFormatted)", "Total: \(app.totalSizeFormatted)"))
                        .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }

                // 1. App binary itself
                HStack(spacing: 6) {
                    Image(systemName: "app.fill")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(Color.accentColor)
                    Text(tr("File cài đặt ứng dụng (.app)", "App bundle (.app)"))
                        .font(.system(size: FS.caption, weight: .medium))
                    Spacer()
                    Text(SystemCleanerManager.formatBytes(app.appSizeBytes))
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))

                // 2. Leftovers
                if app.isInspectingLeftovers {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(tr("Đang dò tìm file rác (Caches, Application Support...)...", "Searching for leftover files (Caches, Support...)..."))
                            .font(.system(size: FS.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                } else if app.leftovers.isEmpty {
                    Text(tr("Không tìm thấy file rác ngoài thư mục .app.", "No leftover files found outside .app bundle."))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                        .padding(4)
                } else {
                    ForEach(app.leftovers.indices, id: \.self) { idx in
                        let item = app.leftovers[idx]
                        HStack(spacing: 6) {
                            Toggle("", isOn: Binding<Bool>(
                                get: {
                                    cleanerManager.selectedApp?.leftovers[idx].isSelected ?? true
                                },
                                set: { val in
                                    cleanerManager.selectedApp?.leftovers[idx].isSelected = val
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.localizedCategoryName)
                                    .font(.system(size: FS.caption, weight: .semibold))
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: FS.caption))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(item.sizeFormatted)
                                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.02)))
                    }
                }
            }

            // Uninstall Action Button
            Button {
                cleanerManager.uninstallSelectedApp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: FS.caption, weight: .semibold))
                    Text(cleanerManager.isUninstalling ? tr("Đang gỡ sạch...", "Uninstalling...") : tr("Gỡ bỏ tận gốc (\(app.totalSizeFormatted))", "Uninstall Completely (\(app.totalSizeFormatted))"))
                        .font(.system(size: FS.caption, weight: .semibold))
                }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .foregroundStyle(Color.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(cleanerManager.isUninstalling)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - SECTION 2: LARGE & OLD FILES

    private var largeFilesSection: some View {
        VStack(spacing: 8) {
            // Header with threshold selector
            HStack(spacing: 6) {
                Text(tr("Ngưỡng kích thước:", "Size threshold:"))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)

                ForEach([100, 200, 500, 1000], id: \.self) { mb in
                    Button {
                        cleanerManager.largeFileThresholdMB = mb
                        cleanerManager.scanLargeFiles()
                    } label: {
                        Text(mb >= 1000 ? "≥ 1GB" : "≥ \(mb)MB")
                            .font(.system(size: FS.caption, weight: cleanerManager.largeFileThresholdMB == mb ? .semibold : .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(cleanerManager.largeFileThresholdMB == mb ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(cleanerManager.largeFileThresholdMB == mb ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    cleanerManager.scanLargeFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: FS.caption, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(tr("Quét lại tệp lớn", "Rescan large files"))
            }
            .padding(.horizontal, 2)

            if cleanerManager.isScanningLargeFiles {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(tr("Đang quét các tệp lớn trong Downloads, Movies, Documents...", "Scanning large files in Downloads, Movies, Documents..."))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            } else if cleanerManager.largeFiles.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: FS.display))
                        .foregroundStyle(.secondary)
                    Text(tr("Không có tệp nào lớn hơn \(cleanerManager.largeFileThresholdMB)MB.", "No files larger than \(cleanerManager.largeFileThresholdMB)MB found."))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            } else {
                VStack(spacing: 4) {
                    ForEach(cleanerManager.largeFiles) { file in
                        largeFileRow(file: file)
                    }
                }
            }
        }
    }

    private func largeFileRow(file: LargeFileItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: file.icon)
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(file.kind) • \(file.relativeDateFormatted)")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(file.sizeFormatted)
                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)

            // Reveal in Finder button
            Button {
                cleanerManager.revealInFinder(file.url)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(tr("Mở trong Finder", "Reveal in Finder"))

            // Move to Trash button
            Button {
                cleanerManager.trashLargeFile(file)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.red)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.red.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(tr("Chuyển vào Thùng rác", "Move to Trash"))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
