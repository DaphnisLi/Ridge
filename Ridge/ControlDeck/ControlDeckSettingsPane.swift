import SwiftUI

/// 设置侧栏「控制台」：开关与能力说明；不与小组件库混排。
struct ControlDeckSettingsPane: View {
    @ObservedObject private var settings = ControlDeckSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard
                enableCard
                modulesCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            IslandController.shared?.beginSettingsSessionCollapsed()
            AppLog.debug("ControlDeck", "控制台设置页已显示", ["enabled": settings.isEnabled])
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制台")
                .font(.system(size: 22, weight: .semibold))
            Text("类似手机控制中心：集中放电量、音量、防休眠等功能性磁贴。会议倒计时等内容型信息仍在「小组件」里各自成页，不会塞进控制台。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在灵动岛显示控制台")
                        .font(.system(size: 14, weight: .semibold))
                    Text(settings.isEnabled
                         ? "已开启。展开岛后可左右滑动到控制台页（高度为普通页两倍）。"
                         : "最多一个控制台。开启后会出现在岛的分页中。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { enabled in
                            settings.setEnabled(enabled)
                            if enabled {
                                WidgetRuntime.shared.focusControlDeck()
                            } else {
                                WidgetRuntime.shared.recompute(reason: "controlDeckOff")
                            }
                            IslandController.shared?.beginSettingsSessionCollapsed()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if settings.isEnabled {
                Button {
                    WidgetRuntime.shared.focusControlDeck()
                    IslandController.shared?.beginSettingsSession()
                    AppLog.info("ControlDeck", "设置页预览控制台")
                } label: {
                    Label("在岛上预览控制台", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
    }

    private var modulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("规划中的功能模块")
                .font(.system(size: 15, weight: .semibold))
            Text("以下能力将逐步接入控制台；与「小组件」库相互独立，无需拖拽放入。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(settings.plannedModules) { module in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                            Image(systemName: module.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(module.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text("即将推出")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(SettingsChrome.cardStroke.opacity(0.85), lineWidth: SettingsChrome.cardStrokeWidth)
                            )
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
    }
}
