import CoreAudio
import SwiftUI

/// 控制台声音组件：主输出 + 设备切换 + 按 App 混音。
struct SoundMixerDeckView: View {
    @ObservedObject private var sound = SoundSession.shared

    private let accent = Color(red: 0.678, green: 0.776, blue: 1.0) // #adc6ff
    private let accentGreen = Color(red: 0.325, green: 0.882, blue: 0.435) // #53e16f
    private let blueMid = Color(red: 0.510, green: 0.659, blue: 1.0) // #82a8ff
    /// 滚动视口实心底：避免半透明行在 clipped 边缘闪岛黑。
    private let scrollViewportFill = Color(nsColor: NSColor(calibratedWhite: 0.05, alpha: 1))

    private var displayOutputs: [SoundOutputDevice] {
        SoundMixerDebugMock.enabled ? SoundMixerDebugMock.devices : sound.outputDevices
    }

    private var displayApps: [SoundAppRow] {
        SoundMixerDebugMock.enabled ? SoundMixerDebugMock.apps : sound.apps
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let leftW = (geo.size.width - gap) * (5.0 / 12.0)
            let rightW = geo.size.width - gap - leftW
            HStack(alignment: .top, spacing: gap) {
                masterColumn
                    .frame(width: leftW, height: geo.size.height, alignment: .topLeading)
                appsColumn
                    .frame(width: rightW, height: geo.size.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            sound.start()
            AppLog.warn("Sound", "混音台页已显示", [
                "outputs": displayOutputs.count,
                "apps": displayApps.count,
                "mock": SoundMixerDebugMock.enabled
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sound.mixerTitle)
    }

    // MARK: - Left: master + devices

    private var masterColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(accent)
                        Text(L10n.Sound.masterOutputVolume)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Text("\(percent(sound.masterVolume))%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                MixerGradientTrack(
                    value: Binding(
                        get: { sound.masterVolume },
                        set: { next in
                            AppLog.info("Sound", "主音量拖动", ["volume": String(format: "%.2f", next)])
                            sound.setMasterVolume(next)
                        }
                    ),
                    gradient: Gradient(colors: [
                        Color(red: 0.23, green: 0.51, blue: 1.0),
                        blueMid,
                        accent
                    ]),
                    glow: accent.opacity(0.45)
                )
                .frame(height: 10)
            }

            Text(L10n.Sound.currentOutputDevice)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if displayOutputs.isEmpty {
                Text(L10n.Sound.noOutputDevices)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                // 选中 / 未选中同一列表一起滑，仅样式不同。
                AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orderedOutputs) { device in
                            if device.isDefault {
                                selectedDeviceCard(device)
                            } else {
                                otherDeviceRow(device)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground)
    }

    /// 当前输出置顶，其余保持原序，整表可滚。
    private var orderedOutputs: [SoundOutputDevice] {
        let outputs = displayOutputs
        let selected = outputs.filter(\.isDefault)
        let others = outputs.filter { !$0.isDefault }
        return selected + others
    }

    private func otherDeviceRow(_ device: SoundOutputDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: deviceSymbol(for: device))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 16)
            Text(device.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let battery = device.batteryPercent {
                batteryBadge(percent: battery, emphasized: false)
            } else if device.transport == kAudioDeviceTransportTypeBuiltIn {
                Text(L10n.Sound.builtInHint)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            selectOutputDevice(device)
        }
    }

    private func selectedDeviceCard(_ device: SoundOutputDevice) -> some View {
        // ZStack 铺满宽度画底，避免滚动时 `.background` 与对勾分层裁切。
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentGreen.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accentGreen.opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: deviceSymbol(for: device))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentGreen)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(L10n.Sound.activeOutput)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if let battery = device.batteryPercent {
                        batteryBadge(percent: battery, emphasized: true)
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentGreen)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            selectOutputDevice(device)
        }
    }

    private func selectOutputDevice(_ device: SoundOutputDevice) {
        guard !SoundMixerDebugMock.enabled else {
            AppLog.debug("Sound", "调试假数据：忽略切换输出", ["uid": device.uid])
            return
        }
        guard !device.isDefault else { return }
        AppLog.info("Sound", "点击切换输出设备", [
            "name": device.name,
            "uid": device.uid
        ])
        sound.selectOutput(uid: device.uid)
    }

    private func batteryBadge(percent: Int, emphasized: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: batterySymbol(percent))
                .font(.system(size: emphasized ? 13 : 12))
            Text("\(percent)%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(emphasized ? accentGreen : Color.white.opacity(0.55))
        .accessibilityLabel(L10n.Sound.batteryPercent(percent))
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 0..<15: return "battery.0percent"
        case 15..<35: return "battery.25percent"
        case 35..<60: return "battery.50percent"
        case 60..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: - Right: apps

    private var appsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(L10n.Sound.perAppMix)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                Text(L10n.Sound.activeSources(displayApps.count))
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(accentGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accentGreen.opacity(0.12))
                    )
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            Group {
                if displayApps.isEmpty {
                    Text(L10n.Sound.noActiveApps)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.40))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 12)
                } else {
                    AlwaysVisibleScrollView(viewportFill: scrollViewportFill) {
                        VStack(spacing: 10) {
                            ForEach(displayApps.prefix(8)) { app in
                                appRow(app)
                            }
                        }
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if sound.tapAvailability != .available {
                Text(tapHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AppLog.info("Sound", "点击授权屏幕录制")
                        sound.requestScreenCaptureAccess()
                    }
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground)
    }

    private func appRow(_ app: SoundAppRow) -> some View {
        let displayVolume = app.isMuted ? 0.0 : app.volume
        let tint: Color = app.isMuted ? Color.red.opacity(0.75) : accent

        return HStack(spacing: 8) {
            appIcon(app)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Text(appSubtitle(app))
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(
                        app.isMuted ? Color.red.opacity(0.85) : .white.opacity(0.40)
                    )
                    .lineLimit(1)
            }
            .frame(width: 72, alignment: .leading)

            MixerGradientTrack(
                value: Binding(
                    get: { displayVolume },
                    set: { next in
                        guard !SoundMixerDebugMock.enabled else { return }
                        AppLog.info("Sound", "App 音量拖动", [
                            "key": app.key,
                            "volume": String(format: "%.2f", next)
                        ])
                        sound.setAppVolume(next, for: app.key)
                    }
                ),
                gradient: Gradient(colors: [tint.opacity(0.85), tint]),
                glow: tint.opacity(0.25),
                trackHeight: 8
            )
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .opacity(app.isPlaying || app.isMuted || app.volume < 0.999 ? 1 : 0.55)

            Text("\(percent(displayVolume))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(app.isMuted ? Color.red.opacity(0.85) : .white.opacity(0.80))
                .frame(width: 32, alignment: .trailing)

            Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(app.isMuted ? Color.red.opacity(0.90) : .white.opacity(0.70))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(app.isMuted ? Color.red.opacity(0.20) : Color.white.opacity(0.06))
                )
                .onTapGesture {
                    guard !SoundMixerDebugMock.enabled else { return }
                    AppLog.info("Sound", "点击 App 静音切换", [
                        "key": app.key,
                        "wasMuted": app.isMuted,
                        "nextMuted": !app.isMuted
                    ])
                    sound.setAppMuted(!app.isMuted, for: app.key)
                }
                .help(app.isMuted ? L10n.Sound.unmuteApp : L10n.Sound.muteApp)
        }
        .opacity(app.isMuted ? 0.78 : 1)
    }

    private func appIcon(_ app: SoundAppRow) -> some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }

    private func appSubtitle(_ app: SoundAppRow) -> String {
        if app.isMuted { return L10n.Sound.appMutedNow }
        if app.isPlaying { return L10n.Sound.appPlaying }
        return L10n.Sound.appIdle
    }

    private var tapHint: String {
        switch sound.tapAvailability {
        case .available: return ""
        case .needsMacOS142: return L10n.Sound.needsMacOS142Body
        case .needsScreenCapture: return L10n.Sound.grantScreenCapture
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func percent(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private func deviceSymbol(for device: SoundOutputDevice) -> String {
        switch device.transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            let lower = device.name.lowercased()
            if lower.contains("headphone") || lower.contains("耳机") {
                return "headphones"
            }
            return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAirPlay:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            let lower = device.name.lowercased()
            if lower.contains("headphone") || lower.contains("airpods") || lower.contains("耳机") {
                return "headphones"
            }
            return "hifispeaker.fill"
        default:
            let lower = device.name.lowercased()
            if lower.contains("airpods") || lower.contains("headphone") || lower.contains("耳机") {
                return "headphones"
            }
            if lower.contains("display") || lower.contains("hdmi") || lower.contains("外接") {
                return "hifispeaker.fill"
            }
            return "laptopcomputer"
        }
    }
}

// MARK: - Custom track

private struct MixerGradientTrack: View {
    @Binding var value: Double
    var gradient: Gradient
    var glow: Color
    var trackHeight: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let clamped = min(1, max(0, value))
            let fillW = w * clamped
            let knob: CGFloat = trackHeight + 4

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fillW, trackHeight / 2), height: trackHeight)
                    .shadow(color: glow, radius: 6, y: 0)

                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                    )
                    .offset(x: max(0, min(w - knob, fillW - knob / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = min(1, max(0, drag.location.x / w))
                    }
            )
        }
    }
}
