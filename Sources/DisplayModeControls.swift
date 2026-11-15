// SPDX-License-Identifier: GPL-3.0-only
// Hallmark · component: display mode menus · genre: modern-minimal · theme: HyperMac native
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4
// Native hover/focus/pressed/disabled, inline applying/error states, and reversible success.
import SwiftUI
import CoreGraphics

struct DisplayModeControls<Trailing: View>: View {
    let displayID: CGDirectDisplayID
    @ObservedObject var manager: DisplayModeManager
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let catalog = manager.catalogs[displayID] {
                    Menu {
                        ForEach(catalog.resolutions) { resolution in
                            Button { manager.selectResolution(resolution, for: displayID) } label: {
                                if resolution == catalog.current.resolution {
                                    Label(resolution.title, systemImage: "checkmark")
                                } else { Text(resolution.title) }
                            }
                        }
                    } label: {
                        Text("\(catalog.current.resolution.width) × \(catalog.current.resolution.height)").lineLimit(1)
                    }
                    .fixedSize()
                    .disabled(catalog.resolutions.count < 2 || manager.applyingDisplay != nil)
                    .help(catalog.current.resolution.title + " — " + tr("Độ phân giải giao diện; HiDPI giúp chữ sắc nét hơn.", "UI resolution; HiDPI provides sharper text."))
                    .accessibilityLabel(tr("Độ phân giải màn hình", "Display resolution"))
                    .accessibilityValue(catalog.current.resolution.title)

                    Menu {
                        ForEach(catalog.rates(for: catalog.current.resolution)) { option in
                            Button { manager.select(option, for: displayID) } label: {
                                if option == catalog.current {
                                    Label(option.refreshTitle, systemImage: "checkmark")
                                } else { Text(option.refreshTitle) }
                            }
                        }
                    } label: {
                        Text(catalog.current.milliHertz == 0 ? tr("Tự động", "Auto") : catalog.current.refreshTitle).lineLimit(1)
                    }
                    .fixedSize()
                    .disabled(catalog.rates(for: catalog.current.resolution).count < 2 || manager.applyingDisplay != nil)
                    .help(tr("Tần số quét: chỉ hiện Hz được macOS hỗ trợ ở độ phân giải này.", "Refresh rate: only modes supported by macOS at this resolution are listed."))
                    .accessibilityLabel(tr("Tần số quét màn hình", "Display refresh rate"))
                    .accessibilityValue(catalog.current.refreshTitle)
                } else {
                    Text(tr("Chưa có chế độ màn hình", "Display modes unavailable"))
                        .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                trailing()
            }
            .controlSize(.mini)
            .font(.system(size: FS.caption, weight: .medium))
            if manager.catalogs[displayID]?.isMirrored == true {
                Text(tr("Đang phản chiếu: thay đổi có thể ảnh hưởng các màn cùng nhóm.", "Mirroring: changes may affect other displays in this group."))
                    .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.applyingDisplay == displayID {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(tr("Đang đổi chế độ…", "Applying display mode…"))
                        .font(.system(size: FS.caption))
                }
            }
            if let error = manager.errors[displayID] {
                Text(error).font(.system(size: FS.caption)).foregroundStyle(Tone.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if manager.previous[displayID] != nil {
                Button(tr("Hoàn tác chế độ màn hình", "Undo display mode change")) { manager.undo(for: displayID) }
                    .font(.system(size: FS.caption)).controlSize(.small)
                    .disabled(manager.applyingDisplay != nil)
            }
        }
    }
}
