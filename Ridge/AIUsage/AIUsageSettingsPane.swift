import SwiftUI

/// 设置页：岛预览三态 + 三阶阈值卡 + Cursor 双槽 Bento。
struct AIUsageWidgetConfigSection: View {
    @ObservedObject private var settings = AIUsageSettings.shared
    @ObservedObject private var session = AIUsageSession.shared
    @State private var previewStage: AIUsageStage = .abundant

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.Spacing.stack) {
                    islandStage
                    thresholdsBento
                    cursorProviderCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                settings.restoreDefaults()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            AIUsageSession.shared.start()
            Task { await AIUsageSession.shared.refresh(reason: "settingsAppear") }
            AppLog.debug("AIUsage", "设置配置区已显示")
        }
    }

    // MARK: - 岛预览三态

    private var islandStage: some View {
        SettingsIslandStage(
            options: [
                stageOption(.abundant, badge: "\(settings.abundantThreshold)%"),
                stageOption(.warning, badge: "\(settings.warningThreshold)%"),
                stageOption(.critical, badge: "\(settings.criticalThreshold)%")
            ],
            selection: Binding(
                get: { previewStage.rawValue },
                set: { previewStage = AIUsageStage(rawValue: $0) ?? .abundant }
            )
        ) { option in
            let stage = AIUsageStage(rawValue: option.id) ?? .abundant
            // 与会议 tip 同款：预览壳无 IslandChrome，舞台只补左右/底。
            AIUsageIslandCardView.previewSample(stage: stage, compact: true)
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: 34)
                .id("\(stage.rawValue)-\(settings.abundantThreshold)-\(settings.warningThreshold)-\(settings.criticalThreshold)")
        }
    }

    private func stageOption(_ stage: AIUsageStage, badge: String) -> SettingsIslandStageOption {
        SettingsIslandStageOption(
            id: stage.rawValue,
            title: stage.label,
            badge: badge,
            symbol: "circle.fill",
            tint: stage.settingsAccent,
            maxIslandWidth: SettingsIslandPreviewWidth.tip,
            hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
            bottomRadius: 18,
            outlineStyle: .panel,
            minStageHeight: 88,
            compactShell: true
        )
    }

    // MARK: - 三阶阈值卡

    private var thresholdsBento: some View {
        SettingsBentoCard {
            SettingsBentoCardTitle(
                symbol: "slider.horizontal.3",
                tint: SettingsChrome.primary,
                title: L10n.AIUsage.thresholdsTitle
            )

            HStack(alignment: .top, spacing: 10) {
                thresholdPill(
                    stage: .abundant,
                    title: L10n.AIUsage.thresholdAbundantStage,
                    rangeText: L10n.AIUsage.thresholdRangeAbundant,
                    prefix: "≤",
                    value: Binding(
                        get: { settings.abundantThreshold },
                        set: { settings.abundantThreshold = $0 }
                    ),
                    range: 50...80
                )
                thresholdPill(
                    stage: .warning,
                    title: L10n.AIUsage.thresholdWarningStage,
                    rangeText: L10n.AIUsage.thresholdRangeWarning,
                    prefix: "≤",
                    value: Binding(
                        get: { settings.warningThreshold },
                        set: { settings.warningThreshold = $0 }
                    ),
                    range: 20...45
                )
                thresholdPill(
                    stage: .critical,
                    title: L10n.AIUsage.thresholdCriticalStage,
                    rangeText: L10n.AIUsage.thresholdRangeCritical,
                    prefix: "≤",
                    value: Binding(
                        get: { settings.criticalThreshold },
                        set: { settings.criticalThreshold = $0 }
                    ),
                    range: 5...15
                )
            }
        }
    }

    private func thresholdPill(
        stage: AIUsageStage,
        title: String,
        rangeText: String,
        prefix: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stage.settingsAccent)
                    .frame(width: 10, height: 10)
                    .shadow(color: stage.settingsAccent.opacity(0.7), radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SettingsChrome.Font.cardTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rangeText)
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }

            HStack(spacing: 6) {
                Text(prefix)
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(stage.settingsAccent)
                Text("\(value.wrappedValue)")
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .frame(minWidth: 22, alignment: .trailing)
                Text("%")
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Button {
                        value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsChrome.outlineVariant.opacity(0.4), lineWidth: 1)
                    )
            )

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettingsChrome.surfaceContainer)
                    Capsule()
                        .fill(stage.settingsAccent)
                        .frame(width: max(4, geo.size.width * CGFloat(value.wrappedValue) / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(stage.settingsAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Cursor 双槽卡

    private var cursorProviderCard: some View {
        let snap = session.snapshot?.cursor
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.AIUsage.providersTitle)
                    .font(SettingsChrome.Font.sectionTitle)
            }
            .foregroundStyle(SettingsChrome.onSurface)

            SettingsBentoCard {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(SettingsChrome.primary.opacity(0.10))
                            Image(systemName: "terminal")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SettingsChrome.primary)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(L10n.AIUsage.providerCursor)
                                    .font(SettingsChrome.Font.sectionTitle)
                                    .foregroundStyle(SettingsChrome.onSurface)
                                if let plan = snap?.planLabel {
                                    Text(plan)
                                        .font(SettingsChrome.Font.monoCaption)
                                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(SettingsChrome.surfaceContainer)
                                        )
                                }
                            }
                            Text(L10n.AIUsage.expandedSubtitle)
                                .font(SettingsChrome.Font.caption)
                                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        }
                    }
                    Spacer()
                    Text(L10n.AIUsage.cursorQuotaHint)
                        .font(SettingsChrome.Font.monoCaption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(SettingsChrome.surfaceContainer)
                        )
                }

                if let err = snap?.errorMessage, snap?.windows.isEmpty != false {
                    Text(err)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.error)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        planSlot(snap?.windows.first)
                        onDemandSlot(snap?.onDemand)
                    }
                }
            }
        }
    }

    private func planSlot(_ window: AIUsageWindow?) -> some View {
        let remaining = window?.remainingPercent ?? 0
        let stage = settings.stage(forRemaining: remaining)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.AIUsage.windowPlanTotalCycle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                Spacer()
                Text(stage.label)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(stage.settingsAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(stage.settingsAccent.opacity(0.12))
                    )
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(L10n.AIUsage.remainingLabel)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text("\(Int(remaining.rounded()))%")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(stage.settingsAccent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettingsChrome.surfaceContainer)
                    Capsule()
                        .fill(stage.settingsAccent)
                        .frame(width: max(4, geo.size.width * CGFloat(remaining / 100)))
                }
            }
            .frame(height: 8)
            Text(
                window.flatMap(\.resetsAt).map(AIUsageIslandCardView.notchResetBadge)
                    ?? L10n.AIUsage.resetUnknown
            )
            .font(SettingsChrome.Font.monoCaption)
            .foregroundStyle(SettingsChrome.onSurfaceVariant)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(stage.settingsAccent.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(stage.settingsAccent.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private func onDemandSlot(_ spend: AIUsageOnDemandSpend?) -> some View {
        let spent = spend?.spentUSD ?? 0
        let limit = spend?.limitUSD ?? 0
        let occ = spend?.occupancyPercent ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.AIUsage.onDemandTitle)
                    .font(SettingsChrome.Font.cardTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(L10n.AIUsage.onDemandNoReset)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsChrome.surfaceContainer)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.AIUsage.onDemandSettled)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Text(String(format: "$%.2f", spent))
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(SettingsChrome.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsChrome.outlineVariant.opacity(0.3), lineWidth: 1)
                    )
            )

            if limit > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.AIUsage.onDemandOccupancy(occ))
                            .font(SettingsChrome.Font.monoCaption)
                        Spacer()
                        Text(L10n.AIUsage.onDemandRemaining(limit - spent))
                            .font(SettingsChrome.Font.monoCaption)
                    }
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SettingsChrome.surfaceContainer)
                            Capsule()
                                .fill(SettingsChrome.primary)
                                .frame(width: max(4, geo.size.width * CGFloat(occ / 100)))
                        }
                    }
                    .frame(height: 10)
                }
            }

            if limit > 0 {
                HStack {
                    Spacer()
                    Text(L10n.AIUsage.onDemandSoftLimit(limit))
                        .font(SettingsChrome.Font.cardTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.outlineVariant.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
