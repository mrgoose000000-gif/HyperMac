import SwiftUI

/// Thẻ điều khiển quạt kiểu iStat Menus: System Controlled / Medium / High + thanh trượt %.
struct FanControlCardView: View {
    @ObservedObject var fan: FanManager

    var body: some View {
        if fan.isAvailable {
            VStack(alignment: .leading, spacing: 7) {
                header
                modeRow
                if fan.mode == .curve { curveEditor }
                sliderRow
                statusRow
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: Rad.md).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            )
            .onAppear { syncSlider() }
            .onChange(of: fan.targetRPM) { if !fan.isDragging { syncSlider() } }
            .onChange(of: fan.mode) { if !fan.isDragging { syncSlider() } }
            // Ở chế độ System, thanh trượt bám theo tốc độ quạt thực tế (như iStat Menus).
            .onChange(of: fan.currentRPM) {
                if !fan.isDragging && fan.mode == .system { syncSlider() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: FS.title, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(fan.fanCount > 1 ? tr("Quạt (\(fan.fanCount))", "Fans (\(fan.fanCount))") : tr("Quạt", "Fan"))
                    .font(.system(size: FS.body, weight: .bold))
                Spacer()
                Text("\(Self.fmt(fan.currentRPM)) RPM")
                    .font(.system(size: FS.body, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            rpmBar
        }
    }

    /// Thanh RPM thực tế (0 → max), như thanh quạt trong iStat Menus.
    private var rpmBar: some View {
        GeometryReader { geo in
            let ratio = fan.maxRPM > 0 ? min(max(fan.currentRPM / fan.maxRPM, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(ratio > 0 ? 4 : 0, geo.size.width * ratio))
                    .animation(.easeOut(duration: 0.25), value: ratio)
            }
        }
        .frame(height: 5)
        .accessibilityLabel(tr("Tốc độ quạt thực tế", "Actual fan speed"))
        .accessibilityValue("\(Self.fmt(fan.currentRPM)) RPM")
    }

    private static func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }

    private var modeRow: some View {
        HStack(spacing: 5) {
            modeButton(tr("Hệ thống", "System"), active: fan.mode == .system) { fan.selectSystem() }
            modeButton("Medium", active: fan.mode == .medium) { fan.selectMedium() }
            modeButton("High", active: fan.mode == .high) { fan.selectHigh() }
            modeButton(tr("Đường cong", "Curve"), active: fan.mode == .curve) {
                fan.mode == .curve ? fan.disableCurve() : fan.enableCurve()
            }
        }
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: handleModeTap(action)) {
            Text(title)
                .font(.system(size: FS.label, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// Nếu chưa có helper thì bấm bất kỳ chế độ nào ngoài System sẽ mở cài đặt helper.
    private func handleModeTap(_ action: @escaping () -> Void) -> () -> Void {
        return {
            if !fan.isHelperReady {
                fan.installHelperIfNeeded()
            } else {
                action()
            }
        }
    }

    /// Bảng chỉnh "nhiệt độ → % quạt" (kiểu smcFanControl): chỉnh mốc, chọn nguồn nhiệt, xem live.
    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("Đường cong nhiệt → quạt", "Temp → fan curve"))
                    .font(.system(size: FS.caption, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                // Segmented icon (gọn, không tràn) — rê chuột để xem tên từng nguồn.
                Picker("", selection: $fan.curveTempSource) {
                    ForEach(FanCurveTempSource.allCases, id: \.self) { s in
                        Image(systemName: s.icon)
                            .help(s.label)
                            .tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 108)
                .help(tr("Nguồn nhiệt cho đường cong", "Curve temperature source"))
                .onChange(of: fan.curveTempSource) { fan.saveCurveConfig() }
            }
            ForEach($fan.curvePoints) { $p in
                HStack(spacing: 8) {
                    Text("≥")
                        .foregroundStyle(.secondary)
                    Stepper("\(Int(p.temp))°C", value: $p.temp, in: 30...105, step: 1)
                        .font(.system(size: FS.caption))
                    Spacer()
                    Stepper("\(Int(p.pct))%", value: $p.pct, in: 0...100, step: 5)
                        .font(.system(size: FS.caption))
                }
            }
            .onChange(of: fan.curvePoints) { fan.saveCurveConfig() }
            HStack {
                Text(tr("Hiện tại:", "Now:"))
                Spacer()
                Text("\(Int(fan.curveLiveTemp))°C → \(Int(fan.curveLivePct))%")
                    .font(.system(size: FS.label, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .font(.system(size: FS.caption))
            .foregroundStyle(.secondary)
            Divider()
        }
        .padding(.top, 2)
    }

    private var sliderRow: some View {
        VStack(spacing: 3) {
            HStack {
                Text(fan.mode == .system
                     ? tr("Tự động (hệ thống) · kéo để đặt tay", "Automatic (system) · drag to set manually")
                     : (fan.mode == .manual ? tr("Thủ công", "Manual") : tr("Tốc độ đặt", "Target speed")))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if fan.mode != .system || fan.isDragging {
                    Text("\(Self.fmt(fan.rpm(forPercent: fan.sliderPercent))) RPM (\(Int(fan.sliderPercent.rounded()))%)")
                        .font(.system(size: FS.label, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            Slider(
                value: $fan.sliderPercent,
                in: Double(fan.minPercent)...100,
                onEditingChanged: { editing in
                    fan.isDragging = editing
                    if !editing { commitSlider() }
                }
            )
            .controlSize(.small)
            .disabled(!fan.isHelperReady)
            .accessibilityLabel(tr("Tốc độ quạt thủ công", "Manual fan speed"))
            .accessibilityValue("\(Int(fan.sliderPercent.rounded()))%")
            HStack {
                Text("\(Self.fmt(fan.minRPM)) RPM")
                Spacer()
                Text("\(Self.fmt(fan.maxRPM)) RPM")
            }
            .font(.system(size: FS.caption))
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let msg = fan.errorMessage {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: FS.caption))
                .foregroundStyle(.orange)
        } else if !fan.isHelperReady {
            Button {
                fan.installHelperIfNeeded()
            } label: {
                Label(tr("Cài helper để điều khiển quạt (hỏi mật khẩu 1 lần)",
                         "Install helper to control the fan (asks password once)"),
                      systemImage: "lock.shield")
                    .font(.system(size: FS.caption, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        } else if fan.safetyTripped {
            Label(tr("Quá nóng: quạt do hệ thống điều khiển.", "Too hot: fan under system control."),
                  systemImage: "flame.fill")
                .font(.system(size: FS.caption))
                .foregroundStyle(.red)
        }
    }

    private func syncSlider() {
        if fan.mode == .system || fan.targetRPM <= 0 {
            fan.sliderPercent = max(Double(fan.minPercent), Double(fan.percent(forRPM: fan.currentRPM)))
        } else {
            fan.sliderPercent = Double(fan.percent(forRPM: fan.targetRPM))
        }
    }

    private func commitSlider() {
        guard fan.isHelperReady else { return }
        fan.setManual(rpm: fan.rpm(forPercent: fan.sliderPercent))
    }
}
