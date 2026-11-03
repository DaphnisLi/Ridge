import AppKit
import SwiftUI

/// 控制台「电量与外设」岛页：对齐稿面设备卡片（耳机三格 / 其它进度条）。
struct BatteryDeckView: View {
    /// 非 nil 时用假数据渲染（设置预览），不订阅真实会话。
    var previewDevices: [BatteryDevice]? = nil

    /// 设置页样张设备（始终有内容可看）。库卡预览偏窄，只放 2 台避免挤成一团。
    static var sampleDevices: [BatteryDevice] {
        [
            BatteryDevice(
                id: "sample.airpods",
                name: "AirPods Pro",
                kind: .headphones,
                percent: 78,
                isCharging: false,
                isLow: false,
                leftPercent: 78,
                rightPercent: 74,
                casePercent: 92,
                listeningMode: .noiseCancellation,
                subtitle: L10n.Battery.listeningModeTitle(.noiseCancellation)
            ),
            BatteryDevice(
                id: "sample.mouse",
                name: L10n.Battery.tipSampleMouse,
                kind: .mouse,
                percent: 12,
                isCharging: false,
                isLow: true,
                leftPercent: nil,
                rightPercent: nil,
                casePercent: nil,
                listeningMode: nil,
                subtitle: L10n.Battery.statusCritical
            )
        ]
    }

    var body: some View {
        Group {
            if let previewDevices {
                BatteryDeckCanvas(devices: previewDevices, isPreview: true)
                    .onAppear {
                        AppLog.debug("Battery", "电量控制台样张预览", ["devices": previewDevices.count])
                    }
            } else {
                BatteryDeckLiveHost()
            }
        }
        .accessibilityLabel(L10n.ControlDeck.moduleBattery)
    }
}

/// 真机岛页：订阅会话。预览路径禁止走这里，否则设置库滚动会被电量刷新拖卡。
private struct BatteryDeckLiveHost: View {
    @ObservedObject private var session = BatterySession.shared

    var body: some View {
        BatteryDeckCanvas(devices: session.devices, isPreview: false)
            .onAppear {
                session.start()
                session.refresh(reason: "deckAppear")
                AppLog.info("Battery", "电量控制台页已显示", ["devices": session.devices.count])
            }
    }
}

/// 纯展示画布：不订阅 Session。
private struct BatteryDeckCanvas: View {
    let devices: [BatteryDevice]
    let isPreview: Bool

    /// 稿面 secondary-fixed。
    private let accentGreen = Color(red: 0.447, green: 0.996, blue: 0.533)
    private let accentRed = Color(red: 0.729, green: 0.102, blue: 0.102)
    /// 设备卡片底：更近黑（约 #141414）。
    private let cardFill = Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1))
    private let cardBorder = Color.white.opacity(0.07)

    /// 浮层 Panel 上系统 ScrollView 滚不动；不铺灰底，透出灵动岛黑色。
    private let columnCount = 3
    private let rowSpacing: CGFloat = 8
    private let gridPadTop: CGFloat = 8
    private let gridPadBottom: CGFloat = 8

    var body: some View {
        Group {
            if devices.isEmpty {
                emptyState
            } else {
                // 按视口高度均分行高，避免固定 maxHeight + clipped 把卡片底裁掉。
                GeometryReader { geo in
                    let cols = layoutColumnCount
                    let rows = deviceRows(columns: cols)
                    let rowCount = max(rows.count, 1)
                    let usable = geo.size.height
                        - gridPadTop
                        - gridPadBottom
                        - CGFloat(rowCount - 1) * rowSpacing
                    let fitted = floor(usable / CGFloat(rowCount))
                    // 行少时撑满视口；行多时保底高度，交给滚动。
                    // AirPods 三格黑底需要比进度条略高。
                    let cardH = min(128, max(isPreview ? 112 : 108, fitted))

                    // 设置预览：单行样张，避免 AlwaysVisibleScrollView 在库卡滚动时拖累合成。
                    // 预览列数跟设备数对齐，避免 2 台仍按 3 列挤窄。
                    let grid = VStack(spacing: rowSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                ForEach(row) { device in
                                    deviceCard(device)
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: cardH,
                                            maxHeight: cardH,
                                            alignment: .topLeading
                                        )
                                }
                                if !isPreview, row.count < cols {
                                    ForEach(0..<(cols - row.count), id: \.self) { _ in
                                        Color.clear
                                            .frame(
                                                maxWidth: .infinity,
                                                minHeight: cardH,
                                                maxHeight: cardH
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, isPreview ? 10 : 14)
                    .padding(.top, gridPadTop)
                    .padding(.bottom, gridPadBottom)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Group {
                        if isPreview {
                            grid
                        } else {
                            AlwaysVisibleScrollView(viewportFill: nil) {
                                grid
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .onAppear {
                        AppLog.info("Battery", "电量页布局", [
                            "viewportH": geo.size.height,
                            "rows": rowCount,
                            "cardH": cardH,
                            "devices": devices.count,
                            "preview": isPreview
                        ])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 预览按实际台数排（2 台就两列撑满）；真岛仍固定三列网格。
    private var layoutColumnCount: Int {
        if isPreview {
            return max(1, min(devices.count, columnCount))
        }
        return columnCount
    }

    /// 每行最多 `columns` 张；真岛末行用空白补齐与前排对齐。
    private func deviceRows(columns: Int) -> [[BatteryDevice]] {
        guard !devices.isEmpty else { return [] }
        let step = max(columns, 1)
        return stride(from: 0, to: devices.count, by: step).map { start in
            Array(devices[start..<min(start + step, devices.count)])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "battery.0percent")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(L10n.Battery.emptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(L10n.Battery.emptyHint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card

    private func deviceCard(_ device: BatteryDevice) -> some View {
        let low = device.isLow
        let border = low ? accentRed.opacity(0.35) : cardBorder
        let fill = low ? accentRed.opacity(0.14) : cardFill

        return VStack(alignment: .leading, spacing: 6) {
            header(device)

            if showsSplitBuds(device) {
                airPodsBatteryRow(device, low: low)
            } else {
                meterBlock(device)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            device.percent.map { "\(device.name), \($0)%" } ?? "\(device.name), \(L10n.Battery.statusUnknownBattery)"
        )
    }

    private func showsSplitBuds(_ device: BatteryDevice) -> Bool {
        device.showsSplitBuds
    }

    // MARK: - Header（稿：图标 + 标题/绿副标题 + 右上绿点）

    private func header(_ device: BatteryDevice) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(device.isLow ? accentRed.opacity(0.20) : Color.white.opacity(0.10))
                Image(systemName: headerSymbol(device))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(device.isLow ? accentRed : .white.opacity(0.92))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(headerSubtitle(device))
                    .font(.system(size: 11))
                    .foregroundStyle(headerSubtitleColor(device))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            trailingAccessory(device)
        }
    }

    @ViewBuilder
    private func trailingAccessory(_ device: BatteryDevice) -> some View {
        if device.isCharging {
            chargingBadge
        } else if device.isLow {
            lowBadge
        } else {
            // 所有设备卡片通用：右上角绿点；电量细节只在下方区域。
            Circle()
                .fill(accentGreen)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }

    /// 所有卡片共用头部副标题（绿色）：聆听模式 / 充电中 / 已连接。
    /// 「电量过低」「电量充足」等只出现在下方电量区，避免与标题下重复。
    private func headerSubtitle(_ device: BatteryDevice) -> String {
        if device.isCharging { return L10n.Battery.statusCharging }
        if let mode = device.listeningMode {
            return L10n.Battery.listeningModeTitle(mode)
        }
        return L10n.Battery.statusConnected
    }

    private func headerSubtitleColor(_ device: BatteryDevice) -> Color {
        accentGreen
    }

    private var chargingBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
            Text(L10n.Battery.badgeCharging)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(accentGreen)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(accentGreen.opacity(0.20)))
    }

    private var lowBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            Text(L10n.Battery.badgeNeedCharge)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(accentRed))
    }

    // MARK: - AirPods 三格（黑底小卡片：上图标+文案，下大号电量）

    /// 按设备名选择系统 AirPods 字形（Pro 盒为 wireless 造型，与普通盒不同）。
    private struct AirPodsGlyphs {
        var header: String
        var left: String
        var right: String
        var caseSymbol: String

        static func resolve(name: String) -> AirPodsGlyphs {
            let hay = name.lowercased()
            if hay.contains("max") {
                return AirPodsGlyphs(
                    header: "airpods.max",
                    left: "airpods.max",
                    right: "airpods.max",
                    caseSymbol: "airpods.chargingcase"
                )
            }
            if hay.contains("pro") {
                return AirPodsGlyphs(
                    header: "airpodspro",
                    left: "airpodpro.left",
                    right: "airpodpro.right",
                    caseSymbol: "airpodspro.chargingcase.wireless"
                )
            }
            if hay.contains("gen3") || hay.contains("gen 3") || hay.contains("第3") {
                return AirPodsGlyphs(
                    header: "airpods.gen3",
                    left: "airpod.gen3.left",
                    right: "airpod.gen3.right",
                    caseSymbol: "airpods.gen3.chargingcase.wireless"
                )
            }
            return AirPodsGlyphs(
                header: "airpods",
                left: "airpod.left",
                right: "airpod.right",
                caseSymbol: "airpods.chargingcase"
            )
        }
    }

    private func headerSymbol(_ device: BatteryDevice) -> String {
        if showsSplitBuds(device) {
            return AirPodsGlyphs.resolve(name: device.name).header
        }
        return device.kind.systemSymbol
    }

    private func airPodsBatteryRow(_ device: BatteryDevice, low: Bool) -> some View {
        let glyphs = AirPodsGlyphs.resolve(name: device.name)
        return HStack(spacing: 6) {
            budCell(
                symbol: glyphs.left,
                title: L10n.Battery.leftBud,
                percent: device.leftPercent,
                low: low
            )
            budCell(
                symbol: glyphs.right,
                title: L10n.Battery.rightBud,
                percent: device.rightPercent,
                low: low
            )
            budCell(
                symbol: glyphs.caseSymbol,
                title: L10n.Battery.caseBud,
                percent: device.casePercent,
                low: low
            )
        }
        .padding(.top, 2)
    }

    private func budCell(symbol: String, title: String, percent: Int?, low: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.55))

            Text(percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(low && (percent ?? 100) <= 20 ? accentRed : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.06, alpha: 1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            percent.map { "\(title) \($0)%" } ?? "\(title) \(L10n.Battery.statusUnknownBattery)"
        )
    }

    // MARK: - 单电量进度条

    private func meterBlock(_ device: BatteryDevice) -> some View {
        let low = device.isLow
        let bar = low ? accentRed : accentGreen
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(meterLabel(device))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        device.hasBatteryReading
                            ? (low ? accentRed : accentGreen.opacity(0.95))
                            : Color.white.opacity(0.55)
                    )
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(device.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(low ? accentRed : .white)
                    .tracking(-0.3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    if let percent = device.percent {
                        Capsule()
                            .fill(bar)
                            .frame(width: max(4, geo.size.width * CGFloat(percent) / 100))
                            .shadow(color: bar.opacity(0.55), radius: 4, y: 0)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 2)
    }

    private func meterLabel(_ device: BatteryDevice) -> String {
        if device.isLow { return L10n.Battery.statusCritical }
        if device.isCharging { return L10n.Battery.statusCharging }
        if !device.hasBatteryReading { return L10n.Battery.statusUnknownBattery }
        return device.subtitle
    }
}
