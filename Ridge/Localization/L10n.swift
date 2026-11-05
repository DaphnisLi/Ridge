import Foundation

/// 用户可见文案入口。新增语言时只补 `Localizable.xcstrings` / `InfoPlist.xcstrings`，勿在业务里硬编码中文。
///
/// 用法：`Text(L10n.Settings.island)`、`Button(L10n.Common.restoreDefaults) { … }`
/// 带参数：`L10n.Meeting.leadBadge(10)`
enum L10n {
    // MARK: - Common

    enum Common {
        static var restoreDefaults: String { tr("common.restore_defaults", "恢复默认设置") }
        static var add: String { tr("common.add", "添加") }
        static var delete: String { tr("common.delete", "删除") }
        static var preview: String { tr("common.preview", "预览") }
        static var settings: String { tr("common.settings", "设置") }
        static var quitApp: String { tr("common.quit_app", "退出 Ridge") }
        static var openSystemSettings: String { tr("common.open_system_settings", "打开系统设置") }
        static var requesting: String { tr("common.requesting", "请求中…") }
        static var comingSoon: String { tr("common.coming_soon", "即将推出") }
        static var authorize: String { tr("common.authorize", "授权") }
        static var authorized: String { tr("common.authorized", "已授权") }
        static var minuteUnit: String { tr("common.minute_unit", "分") }
    }

    // MARK: - Settings shell

    enum Settings {
        static var island: String { tr("settings.section.island", "灵动岛") }
        static var controlDeck: String { tr("settings.section.control_deck", "控制台") }
        static var widgets: String { tr("settings.section.widgets", "小组件") }
        static var resourceMonitor: String { tr("settings.section.resource_monitor", "RAM 监控与进程树") }

        static var islandPageTitle: String { tr("settings.island.page_title", "灵动岛设置") }
        static var islandPageSubtitle: String {
            tr(
                "settings.island.page_subtitle",
                "紧凑模块化布局，精细调控色彩、物理几何形变与触觉反馈"
            )
        }
        static var presetTheme: String { tr("settings.island.preset_theme", "预设主题外观") }
        static var themeCountBadge: String { tr("settings.island.theme_count_badge", "5 款精美预设") }
        static var themeClickHint: String { tr("settings.island.theme_click_hint", "点击即刻无缝换肤") }
        static var themeInUse: String { tr("settings.island.theme_in_use", "使用中") }
        static var geometryTitle: String {
            tr("settings.island.geometry_title", "下圆角物理曲率微调")
        }
        static var geometrySubtitle: String {
            tr(
                "settings.island.geometry_subtitle",
                "专为 MacBook 顶部刘海贴合设计，顶部平直贴边，底部双圆角曲率精细调校"
            )
        }
        static var curvatureLabel: String { tr("settings.island.curvature_label", "当前曲率:") }
        static func curvatureBadgeNamed(_ name: String, _ pts: Int) -> String {
            String(format: tr("settings.island.curvature_badge_named_format", "%@ %d pt"), name, pts)
        }
        static func curvatureBadgeCustom(_ pts: Int) -> String {
            String(format: tr("settings.island.curvature_badge_custom_format", "自定义 %d pt"), pts)
        }
        static var geometryPreview: String {
            tr("settings.island.geometry_preview", "下圆角动态形态预览")
        }
        static var geometryPreviewHint: String {
            tr("settings.island.geometry_preview_hint", "顶部平直贴顶 · 双下圆角实时联动")
        }
        static var cornerPresetFlat: String { tr("settings.island.corner_preset_flat", "平角") }
        static var cornerPresetClassic: String { tr("settings.island.corner_preset_classic", "经典") }
        static var cornerPresetDefault: String { tr("settings.island.corner_preset_default", "默认") }
        static var cornerPresetRound: String { tr("settings.island.corner_preset_round", "圆润") }
        static var presetCustom: String { tr("settings.island.preset_custom", "自定义") }
        static var bottomCorner: String { tr("settings.island.bottom_corner", "下圆角曲率半径") }
        static var cornerSquare: String { tr("settings.island.corner_square", "直角") }
        static var cornerRoundMax: String { tr("settings.island.corner_round_max", "最大圆润") }
        static var motionTitle: String { tr("settings.island.motion_title", "动画与触觉感知") }
        static var animationSpeed: String { tr("settings.island.animation_speed", "展开动画速度") }
        static var speedSlow: String { tr("settings.island.speed_slow", "慢") }
        static var speedFast: String { tr("settings.island.speed_fast", "快") }
        static var speedSnap: String { tr("settings.island.speed_snap", "疾速") }
        static var speedStandard: String { tr("settings.island.speed_standard", "标准") }
        static var speedSmooth: String { tr("settings.island.speed_smooth", "丝滑") }
        static var hapticIntensity: String { tr("settings.island.haptic_intensity", "震感强度") }
        static var hapticTapticHint: String { tr("settings.island.haptic_taptic", "Taptic") }
        static var hideInFullscreen: String { tr("settings.island.hide_in_fullscreen", "全屏时禁用灵动岛") }
        static var hideFullscreenBadge: String {
            tr("settings.island.hide_fullscreen_badge", "智能避让免打扰")
        }
        static var hideFullscreenSubtitle: String {
            tr(
                "settings.island.hide_fullscreen_subtitle",
                "运行全屏沉浸应用、游戏或影视全屏播放时自动隐藏，防止视线遮挡与误触"
            )
        }

        static var hapticOff: String { tr("settings.haptic.off", "关") }
        static var hapticLight: String { tr("settings.haptic.light", "轻") }
        static var hapticMedium: String { tr("settings.haptic.medium", "中") }
        static var hapticStrong: String { tr("settings.haptic.strong", "强") }

        static var styleNotch: String { tr("settings.style.notch", "刘海") }
        static var styleNotchSubtitle: String { tr("settings.style.notch_subtitle", "贴合刘海，悬停展开") }
        static var stylePill: String { tr("settings.style.pill", "菜单栏下方胶囊") }
        static var stylePillSubtitle: String { tr("settings.style.pill_subtitle", "浮在菜单栏下方（即将支持）") }

        static var themeMidnight: String { tr("settings.theme.midnight", "经典黑") }
        static var themeAfterglow: String { tr("settings.theme.afterglow", "暖暮余晖") }
        static var themeLumenPark: String { tr("settings.theme.lumen_park", "林荫微光") }
        static var themeGraphite: String { tr("settings.theme.graphite", "中性灰") }
        static var themeTide: String { tr("settings.theme.tide", "深海潮汐") }
    }

    // MARK: - Widgets library

    enum Widgets {
        static var libraryIntro: String {
            tr(
                "widgets.library.intro",
                "打开开关后可在灵动岛展示。功能磁贴与内容型小组件共用此库；拖到另一张卡片可交换内容型顺序。点击卡片进入预览与设置。"
            )
        }
        static var libraryTitle: String { tr("widgets.library.title", "小组件库") }
        static var deckSectionTitle: String { tr("widgets.deck_section_title", "功能磁贴") }
        static var contentSectionTitle: String { tr("widgets.content_section_title", "内容小组件") }
        static var libraryEmpty: String { tr("widgets.library.empty", "暂无可用小组件。") }
        static var notFound: String { tr("widgets.not_found", "找不到该小组件。") }
        static var cannotPreview: String { tr("widgets.cannot_preview", "无法预览") }
        static var pageDotsA11y: String { tr("widgets.page_dots_a11y", "小组件分页") }
        static var pageDotsCornerValueFormat: String {
            tr(
                "widgets.page_dots_corner_value_format",
                "左侧 %d 页，右侧 %d 页，当前第 %d / %d 页"
            )
        }
        static var meetingPreviewTitle: String { tr("widgets.meeting_preview_title", "下一场会议提醒设置") }
        static var mediaPreviewTitle: String { tr("widgets.media_preview_title", "正在播放") }
        static var focusTimerPreviewTitle: String {
            tr("widgets.focus_timer_preview_title", "专注计时")
        }
        static var emptySummary: String { tr("widgets.empty.summary", "尚未添加小组件时的提示") }
        static var emptyTitle: String { tr("widgets.empty.title", "尚未添加小组件") }
        static var emptySubtitle: String { tr("widgets.empty.subtitle", "启用或添加后，内容会显示在这里") }
        static var emptyAdd: String { tr("widgets.empty.add", "去添加小组件") }
    }

    // MARK: - Sound（控制台混音台组件文案）

    enum Sound {
        static var mixerTitle: String { tr("sound.mixer.title", "专业双轨混音台") }
        static var mixerBadge: String { tr("sound.mixer.badge", "Studio Pro") }
        static var masterOutputVolume: String { tr("sound.mixer.master_output", "主输出音量") }
        static var currentOutputDevice: String { tr("sound.mixer.current_output", "当前输出设备") }
        static var activeOutput: String { tr("sound.mixer.active_output", "当前输出") }
        static var builtInHint: String { tr("sound.mixer.built_in", "内建") }
        static func batteryPercent(_ value: Int) -> String {
            String(format: tr("sound.mixer.battery_percent_format", "电量 %d%%"), value)
        }
        static var noOutputDevices: String { tr("sound.mixer.no_outputs", "未发现可用输出设备") }
        static var perAppMix: String { tr("sound.mixer.per_app", "发声应用独立混音") }
        static func activeSources(_ count: Int) -> String {
            String(format: tr("sound.mixer.active_sources_format", "%d 个源激活"), count)
        }
        static var mixerFooterHint: String {
            tr("sound.mixer.footer_hint", "自动跟随发声源")
        }
        static var noActiveApps: String {
            tr("sound.no_active_apps", "当前没有正在播放的 App")
        }
        static var appMutedNow: String { tr("sound.app_muted_now", "当前静音") }
        static var appPlaying: String { tr("sound.app_playing", "正在播放") }
        static var appIdle: String { tr("sound.app_idle", "待机") }
        static var muteApp: String { tr("sound.mute_app", "静音此 App") }
        static var unmuteApp: String { tr("sound.unmute_app", "恢复声音") }
        static var rememberVolumes: String {
            tr("sound.remember_volumes", "记住每 App 音量（重启后恢复）")
        }
        static var resetAppVolumes: String { tr("sound.reset_app_volumes", "重置 App 音量") }
        static var grantScreenCapture: String {
            tr("sound.grant_screen_capture", "授权屏幕录制以启用按 App 音量")
        }
        static var screenCaptureAccess: String {
            tr("sound.screen_capture_access", "屏幕录制权限")
        }
        static var screenCaptureAccessDesc: String {
            tr(
                "sound.screen_capture_access_desc",
                "用于按 App 独立调节音量（不会录制画面）"
            )
        }
        static var screenCaptureAllow: String {
            tr("sound.screen_capture_allow", "授权屏幕录制")
        }
        static var needsMacOS142Body: String {
            tr("sound.needs_macos142_body", "按 App 独立音量需要 macOS 14.2 或更高版本。")
        }
        static var tapUnavailableHint: String {
            tr("sound.tap_unavailable_hint", "按 App 音量暂不可用，请检查系统版本与屏幕录制权限")
        }
        static var mixerPrefsTitle: String { tr("sound.mixer.prefs_title", "混音台选项") }
        static var mixerPrefsIntro: String {
            tr(
                "sound.mixer.prefs_intro",
                "混音台在控制台页展示。按 App 音量需 macOS 14.2+ 与屏幕录制权限（不会录制画面）。"
            )
        }
        static var moduleLive: String { tr("sound.module_live", "已启用") }
        static var previewDeviceSpeakers: String {
            tr("sound.preview.device_speakers", "MacBook Pro 扬声器")
        }
        static var previewDeviceAirPods: String {
            tr("sound.preview.device_airpods", "AirPods Pro")
        }
        static var previewAppMusic: String { tr("sound.preview.app_music", "音乐") }
        static var previewAppSafari: String { tr("sound.preview.app_safari", "Safari") }
    }

    // MARK: - Control deck

    enum ControlDeck {
        static var title: String { tr("control_deck.title", "控制台") }
        static var intro: String {
            tr(
                "control_deck.intro",
                "类似手机控制中心：集中放电量、音量、防休眠等功能性磁贴。会议倒计时等内容型信息仍在「小组件」里各自成页，不会塞进控制台。"
            )
        }
        static var showOnIsland: String { tr("control_deck.show_on_island", "在灵动岛显示控制台") }
        static var enabledHint: String {
            tr(
                "control_deck.enabled_hint",
                "已开启。展开岛后可左右滑动到混音台页（约 660×300，高于普通页）。"
            )
        }
        static var disabledHint: String {
            tr("control_deck.disabled_hint", "最多一个控制台。开启后会出现在岛的分页中。")
        }
        static var previewOnIsland: String { tr("control_deck.preview_on_island", "在岛上预览控制台") }
        static var plannedModules: String { tr("control_deck.planned_modules", "规划中的功能模块") }
        static var plannedIntro: String {
            tr("control_deck.planned_intro", "以下能力将逐步接入控制台；与「小组件」库相互独立，无需拖拽放入。")
        }

        static var moduleBattery: String { tr("control_deck.module.battery", "电量与外设") }
        static var moduleBatterySummary: String {
            tr("control_deck.module.battery_summary", "已连接外设电量；低电与满电经岛内瞬时通知提示")
        }
        static var moduleVolume: String { tr("control_deck.module.volume", "输出音量") }
        static var moduleProjects: String { tr("control_deck.module.projects", "项目释放") }
        static var moduleShelf: String { tr("control_deck.module.shelf", "货架与剪贴板") }
        static var moduleShelfSummary: String {
            tr(
                "control_deck.module.shelf_summary",
                "拖文件暂存到刘海，并找回复制过的文字、链接、颜色与截图"
            )
        }
        static var moduleVolumeSummary: String {
            tr("control_deck.module.volume_summary", "快速调节系统与按 App 输出音量")
        }
        static var moduleVolumeSummaryLive: String {
            tr(
                "control_deck.module.volume_summary_live",
                "控制台混音台：主输出、设备切换、按 App 独立音量"
            )
        }
        static var moduleFocus: String { tr("control_deck.module.focus", "专注与防休眠") }
        static var moduleFocusSummary: String {
            tr("control_deck.module.focus_summary", "保持唤醒、计时专注等快捷操作")
        }
        static var moduleSystem: String { tr("control_deck.module.system", "系统状态") }
        static var moduleSystemSummary: String {
            tr("control_deck.module.system_summary", "CPU、内存等瞬时读数")
        }

        static var nowPlaying: String { tr("control_deck.tile.now_playing", "正在播放") }
        static var mediaSoon: String { tr("control_deck.tile.media_soon", "媒体控制即将接入") }
        static var weather: String { tr("control_deck.tile.weather", "天气") }
        static var weatherSoon: String { tr("control_deck.tile.weather_soon", "稍后接入") }
        static var keepAwake: String { tr("control_deck.tile.keep_awake", "防休眠") }
        static var focus: String { tr("control_deck.tile.focus", "专注") }
        static var system: String { tr("control_deck.tile.system", "系统") }
        static var systemMetersSoon: String {
            tr("control_deck.tile.system_meters_soon", "CPU / 内存读数即将接入")
        }
    }

    // MARK: - AI Usage（额度监测）

    enum AIUsage {
        static var widgetName: String { tr("ai_usage.widget.name", "AI 额度") }
        static var widgetSummary: String {
            tr(
                "ai_usage.widget.summary",
                "后台监测 Cursor 额度；触达充裕 / 警戒 / 截流阈值时岛上提示约 3 秒"
            )
        }
        static var bannerTitle: String {
            tr("ai_usage.banner.title", "AI 额度梯级预警感知提醒")
        }
        static var sensingTitle: String { tr("ai_usage.sensing.title", "感知总开关") }
        static var sensingSubtitle: String {
            tr(
                "ai_usage.sensing.subtitle",
                "开启后后台感知配额；剩余百分比触达充裕 / 警戒 / 截流任一阈值时，灵动岛瞬时提示约 3 秒。关闭则不弹。"
            )
        }
        static func sensedChannels(_ ready: Int, _ total: Int) -> String {
            String(
                format: tr("ai_usage.sensed_channels_format", "已感知 %d/%d 核心主力通道"),
                ready,
                total
            )
        }
        static var thresholdsTitle: String {
            tr("ai_usage.thresholds.title", "三阶触发百分比阈值精准配置")
        }
        static var thresholdsSubtitle: String {
            tr(
                "ai_usage.thresholds.subtitle",
                "触达充裕 / 警戒 / 截流任一设定值时，灵动岛弹出对应形态胶囊约 3 秒（非常驻页）"
            )
        }
        static var thresholdsValid: String {
            tr("ai_usage.thresholds.valid", "层级校验通过")
        }
        static var thresholdsValidHierarchy: String {
            tr("ai_usage.thresholds.valid_hierarchy", "层级校验通过: 充裕 > 警戒 > 截流")
        }
        static var thresholdAbundant: String {
            tr("ai_usage.threshold.abundant", "充裕态参考阈值")
        }
        static var thresholdWarning: String {
            tr("ai_usage.threshold.warning", "警戒态触发阈值")
        }
        static var thresholdCritical: String {
            tr("ai_usage.threshold.critical", "截流态触发阈值")
        }
        static var thresholdAbundantStage: String {
            tr("ai_usage.threshold.abundant_stage", "充裕态触发阈值 (Stage 01)")
        }
        static var thresholdWarningStage: String {
            tr("ai_usage.threshold.warning_stage", "警戒态触发阈值 (Stage 02)")
        }
        static var thresholdCriticalStage: String {
            tr("ai_usage.threshold.critical_stage", "危机 / 截流阈值 (Stage 03)")
        }
        static var thresholdRangeAbundant: String {
            tr("ai_usage.threshold.range_abundant", "合法范围 50% ~ 80%")
        }
        static var thresholdRangeWarning: String {
            tr("ai_usage.threshold.range_warning", "合法范围 20% ~ 45%")
        }
        static var thresholdRangeCritical: String {
            tr("ai_usage.threshold.range_critical", "合法范围 5% ~ 15%")
        }
        static var providersTitle: String {
            tr("ai_usage.providers.title", "本地 AI 运行环境与模型多维配额")
        }
        static var syncAction: String { tr("ai_usage.sync", "同步") }
        static var providerCursor: String { tr("ai_usage.provider.cursor", "Cursor") }
        static var providerClaude: String { tr("ai_usage.provider.claude", "Claude") }
        static var providerCodex: String { tr("ai_usage.provider.codex", "Codex") }
        static var providerUnavailable: String {
            tr("ai_usage.provider.unavailable", "尚未接入")
        }
        static var planTrial: String { tr("ai_usage.plan.trial", "试用") }
        static var planFree: String { tr("ai_usage.plan.free", "免费") }
        static var stageAbundant: String { tr("ai_usage.stage.abundant", "充裕") }
        static var stageWarning: String { tr("ai_usage.stage.warning", "警戒") }
        static var stageCritical: String { tr("ai_usage.stage.critical", "截流") }
        static var stageCriticalIntense: String {
            tr("ai_usage.stage.critical_intense", "严重不足！")
        }
        static var stageUnknown: String { tr("ai_usage.stage.unknown", "未知") }
        static var remainingLabel: String { tr("ai_usage.remaining", "剩余") }
        static var windowPlanTotal: String {
            tr("ai_usage.window.plan_total", "套餐内金额度")
        }
        static var windowPlanTotalCycle: String {
            tr("ai_usage.window.plan_total_cycle", "套餐内金额度（订阅周期）")
        }
        static var windowPlanAuto: String {
            tr("ai_usage.window.plan_auto", "Auto 额度")
        }
        static var expandedSubtitle: String {
            tr("ai_usage.expanded.subtitle", "Cursor / 月度订阅与弹性按需")
        }
        static var cursorQuotaHint: String {
            tr("ai_usage.cursor.quota_hint", "仅套餐额度有重置 · 按需无重置")
        }
        static var onDemandTitle: String {
            tr("ai_usage.ondemand.title", "按需已花金额（金额，不是额度，无百分比）")
        }
        static var onDemandNoReset: String { tr("ai_usage.ondemand.no_reset", "按需无重置") }
        static var onDemandSettled: String { tr("ai_usage.ondemand.settled", "已结算金额") }
        static var onDemandBillingNote: String {
            tr("ai_usage.ondemand.billing_note", "无重置时刻 / 随月度账单结算")
        }
        static func onDemandOccupancy(_ percent: Double) -> String {
            String(format: tr("ai_usage.ondemand.occupancy_format", "限额占用 %.1f%%"), percent)
        }
        static func onDemandRemaining(_ usd: Double) -> String {
            String(format: tr("ai_usage.ondemand.remaining_format", "剩余可支配 $%.2f"), usd)
        }
        static func onDemandSoftLimit(_ usd: Double) -> String {
            String(format: tr("ai_usage.ondemand.soft_limit_format", "软限制度 $%.2f"), usd)
        }
        static var resetUnknown: String { tr("ai_usage.reset.unknown", "重置时间未知") }
        static var resetSoon: String { tr("ai_usage.reset.soon", "即将重置") }
        static var resetSoonShort: String { tr("ai_usage.reset.soon_short", "即将") }
        static var resetVerb: String { tr("ai_usage.reset.verb", "重置") }
        static var resetRemainHMFormat: String {
            tr("ai_usage.reset.remain_hm_format", "余 %d:%02d")
        }
        static func resetToday(_ time: String) -> String {
            String(format: tr("ai_usage.reset.today_format", "今日 %@ 重置"), time)
        }
        static func resetTomorrow(_ time: String) -> String {
            String(format: tr("ai_usage.reset.tomorrow_format", "明日 %@ 重置"), time)
        }
        static func resetTomorrowShort(_ time: String) -> String {
            String(format: tr("ai_usage.reset.tomorrow_short_format", "明日 %@"), time)
        }
        static func resetAt(_ when: String) -> String {
            String(format: tr("ai_usage.reset.at_format", "%@ 重置"), when)
        }
        static func resetInDays(_ days: Int) -> String {
            String(format: tr("ai_usage.reset.in_days_format", "余 %d 天"), days)
        }
        static func resetInHours(_ hours: Int) -> String {
            String(format: tr("ai_usage.reset.in_hours_format", "余 %dh"), hours)
        }
        static func resetInMinutes(_ minutes: Int) -> String {
            String(format: tr("ai_usage.reset.in_minutes_format", "余 %dm"), minutes)
        }
        static func noticeWarning(_ percent: Int) -> String {
            String(format: tr("ai_usage.notice.warning_format", "Cursor 额度剩余 %d%%，已进入警戒"), percent)
        }
        static func noticeCritical(_ percent: Int) -> String {
            String(format: tr("ai_usage.notice.critical_format", "Cursor 额度剩余 %d%%，接近截流"), percent)
        }
        static var errorNotSignedIn: String {
            tr("ai_usage.error.not_signed_in", "未检测到 Cursor 登录，请先在 Cursor 中登录")
        }
        static var errorKeychain: String {
            tr("ai_usage.error.keychain", "无法读取 Cursor 钥匙串，请在系统弹窗中允许 Ridge 访问")
        }
        static var errorDecrypt: String {
            tr("ai_usage.error.decrypt", "无法解密 Cursor 登录态，请更新 Cursor 后重试")
        }
        static var errorUnauthorized: String {
            tr("ai_usage.error.unauthorized", "Cursor 登录已失效，请重新登录 Cursor")
        }
        static var errorNetwork: String {
            tr("ai_usage.error.network", "暂时无法连接 Cursor 用量服务")
        }
        static var errorGeneric: String {
            tr("ai_usage.error.generic", "读取额度失败")
        }
    }

    // MARK: - Media（正在播放）

    enum Media {
        static var widgetName: String { tr("media.widget.name", "正在播放") }
        static var widgetSummary: String {
            tr("media.widget.summary", "显示封面与播放控制，播放时自动出现在灵动岛")
        }
        static var settingsIntro: String {
            tr(
                "media.settings.intro",
                "系统正在播放音乐、播客或网页媒体时，灵动岛会显示封面、进度与控制按钮。支持拖动进度条跳转。"
            )
        }
        static var playersTitle: String { tr("media.players.title", "支持的播放器") }
        static var playersSubtitle: String {
            tr(
                "media.players.subtitle",
                "读取系统 Now Playing；Apple Music、Spotify、播客与浏览器内网页播放均可。"
            )
        }
        static var playersAllSupported: String {
            tr("media.players.all_supported", "全部已支持")
        }
        static var playerAppleMusic: String { tr("media.player.apple_music", "Apple Music") }
        static var playerSpotify: String { tr("media.player.spotify", "Spotify") }
        static var playerBrowser: String { tr("media.player.browser", "浏览器 / YouTube") }
        static var playerPodcasts: String { tr("media.player.podcasts", "播客") }

        static var previewSampleTitle: String {
            tr("media.preview.sample_title", "Midnight City")
        }
        static var previewSampleArtist: String {
            tr("media.preview.sample_artist", "M83")
        }
        static var idleArtist: String { tr("media.idle_artist", "暂无正在播放的内容") }
        static var unknownArtist: String { tr("media.unknown_artist", "未知艺术家") }

        static var playA11y: String { tr("media.a11y.play", "播放") }
        static var pauseA11y: String { tr("media.a11y.pause", "暂停") }
        static var previousA11y: String { tr("media.a11y.previous", "上一曲") }
        static var nextA11y: String { tr("media.a11y.next", "下一曲") }
        static var shuffleA11y: String { tr("media.a11y.shuffle", "随机播放") }
        static var repeatA11y: String { tr("media.a11y.repeat", "循环播放") }
    }

    // MARK: - Projects（控制台：端口 / 进程按项目释放）

    enum Projects {
        static var deckTitle: String { tr("projects.deck.title", "项目释放") }
        static var widgetSummary: String {
            tr("projects.widget.summary", "监视项目进程占用，结束后经岛内通知提示")
        }
        static var emptyState: String {
            tr("projects.deck.empty", "未发现占用中的项目进程。可在设置中添加项目根目录。")
        }
        static var previewProjectName: String { tr("projects.preview.project_name", "Ridge") }
        static var previewCommandBuild: String { tr("projects.preview.command_build", "xcodebuild") }
        static var previewCommandDev: String { tr("projects.preview.command_dev", "vite") }
        static var previewContainerDB: String { tr("projects.preview.container_db", "postgres") }
        static var previewContainerCache: String { tr("projects.preview.container_cache", "redis") }
        static var runningTitle: String { tr("projects.deck.running", "运行中进程") }
        static var watchingTitle: String { tr("projects.deck.watching", "监视中进程") }
        static var containersTitle: String { tr("projects.deck.containers", "容器 Docker") }
        static var watchingEmpty: String {
            tr("projects.deck.watching_empty", "在左侧点「监视」，进程结束后会在刘海处提示。")
        }
        static var watchAction: String { tr("projects.deck.watch_action", "监视") }
        static var watchingActionOn: String { tr("projects.deck.watching_action_on", "监视中") }
        static var releaseHelp: String {
            tr("projects.deck.release_help", "结束该项目下可释放的进程与容器")
        }
        static var releaseItemHelp: String {
            tr("projects.deck.release_item_help", "结束该命令进程")
        }
        static var cancelWatch: String { tr("projects.deck.cancel_watch", "取消监视") }
        static var expandDetails: String { tr("projects.deck.expand_details", "展开更多") }
        static var treeStreamLabel: String { tr("projects.deck.tree_stream", "TREE STREAM") }
        static var watchingActiveLabel: String { tr("projects.deck.watching_active_label", "ACTIVE") }
        static var durationLabel: String { tr("projects.deck.duration_label", "持续时长") }
        static var cpuUsageLabel: String { tr("projects.deck.cpu_usage", "CPU 占用") }
        static var memoryUsageLabel: String { tr("projects.deck.memory_usage", "物理内存") }
        static var cpuLimitSuffix: String { tr("projects.deck.cpu_limit_suffix", "/ 限额 100%") }
        static var autoNotifyOn: String {
            tr("projects.deck.auto_notify_on", "异常自动通知已开启")
        }
        static func runningStats(_ projects: Int, _ processes: Int) -> String {
            String(
                format: tr("projects.deck.running_stats_format", "%d 工程 · %d 进程"),
                projects,
                processes
            )
        }
        static func watchingActiveCount(_ count: Int) -> String {
            String(format: tr("projects.deck.watching_active_count_format", "%d 活跃"), count)
        }
        static func commandCount(_ count: Int) -> String {
            String(format: tr("projects.deck.command_count_format", "%d 命令"), count)
        }
        static func projectCPU(_ percent: Double) -> String {
            String(format: tr("projects.deck.project_cpu_format", "∑ CPU %.1f%%"), percent)
        }
        static func processMeta(_ pid: Int32, _ cpu: Double, _ mem: String) -> String {
            String(
                format: tr("projects.deck.process_meta_format", "PID %d · CPU %.1f%% · %@"),
                pid,
                cpu,
                mem
            )
        }
        static func memoryPeakInline(_ text: String) -> String {
            String(format: tr("projects.deck.memory_peak_inline_format", "(峰值 %@)"), text)
        }
        static func containersRunningBadge(_ count: Int) -> String {
            String(format: tr("projects.deck.containers_running_badge_format", "%d 运行中"), count)
        }
        static var containerRestart: String { tr("projects.deck.container_restart", "重启") }
        static var containerStop: String { tr("projects.deck.container_stop", "停止") }
        static var containerRestarting: String {
            tr("projects.deck.container_restarting", "正在重启容器…")
        }
        static func containerRestartDone(_ name: String) -> String {
            String(format: tr("projects.deck.container_restart_done_format", "已重启 %@"), name)
        }
        static func containerRestartFailed(_ name: String) -> String {
            String(format: tr("projects.deck.container_restart_failed_format", "重启 %@ 失败"), name)
        }
        static func containerPortBadge(_ ports: [Int]) -> String {
            guard let first = ports.first else { return "" }
            if ports.count == 1 {
                return String(format: tr("projects.deck.container_port_badge_format", "%d"), first)
            }
            let text = ports.prefix(2).map(String.init).joined(separator: "/")
            return text
        }
        static func containerResourceLine(_ cpu: Double, _ mem: String) -> String {
            String(
                format: tr("projects.deck.container_resource_format", "%.1f%% · %@"),
                cpu,
                mem
            )
        }
        static func releaseDone(_ project: String) -> String {
            String(format: tr("projects.deck.release_done_format", "已释放 %@"), project)
        }
        static func releasePartial(_ project: String, _ alive: Int) -> String {
            String(
                format: tr("projects.deck.release_partial_format", "%@ 仍有 %d 个进程未结束"),
                project,
                alive
            )
        }
        static var containersEmpty: String {
            tr("projects.deck.containers_empty", "当前没有运行中的容器。")
        }
        static var watchingHint: String {
            tr("projects.deck.watching_hint", "计时从进程启动算起；结束后会提示成功或失败")
        }
        static func watchingCommand(_ command: String, _ project: String) -> String {
            String(
                format: tr("projects.deck.watching_command_format", "%@ · %@"),
                command,
                project
            )
        }
        static var openLog: String { tr("projects.deck.open_log", "日志") }
        static var viewLog: String { tr("projects.deck.view_log", "查看日志") }
        static var logNotFound: String {
            tr("projects.deck.log_not_found", "未找到该进程的日志文件")
        }
        static var logOpenFailed: String {
            tr("projects.deck.log_open_failed", "无法打开日志文件")
        }
        static var watchOutcomeSuccess: String {
            tr("projects.deck.watch_outcome_success", "执行成功")
        }
        static func watchOutcomeFailed(_ code: Int32) -> String {
            String(format: tr("projects.deck.watch_outcome_failed_format", "执行失败（退出码 %d）"), code)
        }
        static func watchOutcomeSignaled(_ signal: Int32) -> String {
            String(format: tr("projects.deck.watch_outcome_signaled_format", "被信号终止（%@）"), signalName(signal))
        }
        static var watchOutcomeUnknown: String {
            tr("projects.deck.watch_outcome_unknown", "已结束")
        }
        private static func signalName(_ signal: Int32) -> String {
            switch signal {
            case 2: return "SIGINT"
            case 9: return "SIGKILL"
            case 15: return "SIGTERM"
            default: return "\(signal)"
            }
        }
        static func resourceMemCPU(_ mem: String, _ cpu: String) -> String {
            String(format: tr("projects.deck.resource_mem_cpu_format", "%@ · %@"), mem, cpu)
        }
        static func resourceMemCPUPorts(_ mem: String, _ cpu: String, _ ports: String) -> String {
            String(
                format: tr("projects.deck.resource_mem_cpu_ports_format", "%@ · %@ · %@"),
                mem,
                cpu,
                ports
            )
        }
        static func containersSummary(_ count: Int, _ mem: String) -> String {
            String(
                format: tr("projects.deck.containers_summary_format", "%d 个运行中 · 占用 %@"),
                count,
                mem
            )
        }
        static func containersCountOnly(_ count: Int) -> String {
            String(format: tr("projects.deck.containers_count_format", "%d 个运行中"), count)
        }
        static func groupCount(_ count: Int) -> String {
            String(format: tr("projects.deck.group_count_format", "%d 组"), count)
        }
        static var refresh: String { tr("projects.deck.refresh", "刷新") }
        static var release: String { tr("projects.deck.release", "释放") }
        static var pause: String { tr("projects.deck.pause", "暂停") }
        static var stop: String { tr("projects.deck.stop", "停止") }
        static var show: String { tr("projects.deck.show", "查看") }
        static var hide: String { tr("projects.deck.hide", "收起") }
        static var releasing: String { tr("projects.deck.releasing", "释放中") }
        static var unattributed: String { tr("projects.deck.unattributed", "未归属") }
        static var viewOnly: String { tr("projects.deck.view_only", "仅查看") }
        static var watchHelp: String { tr("projects.deck.watch_help", "结束后在灵动岛提示") }
        static var watchNotificationTitle: String {
            tr("projects.watch.notification_title", "开发进程已结束")
        }
        static var watchEndedTitle: String { tr("projects.deck.watch_ended_title", "已结束") }
        static var watchEndedHeadline: String {
            tr("projects.deck.watch_ended_headline", "进程已结束")
        }
        static var watchEndedDismiss: String { tr("projects.deck.watch_ended_dismiss", "知道了") }
        static func watchEnded(_ project: String, _ label: String) -> String {
            String(
                format: tr("projects.watch.ended_format", "%@ · %@ 已结束"),
                project,
                label
            )
        }
        static func watchEndedMessage(
            _ project: String,
            _ label: String,
            _ outcome: ProjectWatchOutcome,
            peakMemoryBytes: UInt64 = 0,
            durationSeconds: TimeInterval = 0
        ) -> String {
            let parts = [
                "\(project) / \(label)",
                outcomeText(outcome),
                durationSeconds > 0 ? durationText(durationSeconds) : nil,
                peakMemoryBytes > 0 ? memoryPeak(peakMemoryBytes) : nil
            ].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
        static func outcomeText(_ outcome: ProjectWatchOutcome) -> String {
            switch outcome {
            case .succeeded: return watchOutcomeSuccess
            case .failed(let code): return watchOutcomeFailed(code)
            case .signaled(let signal): return watchOutcomeSignaled(signal)
            case .unknown: return watchOutcomeUnknown
            }
        }
        static func memoryPeak(_ bytes: UInt64) -> String {
            let text = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
            return String(format: tr("projects.deck.memory_peak_format", "峰值 %@"), text)
        }
        static func memoryUsed(_ bytes: UInt64) -> String {
            let text = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
            return String(format: tr("projects.deck.memory_used_format", "内存 %@"), text)
        }
        static func durationText(_ seconds: TimeInterval) -> String {
            let text: String
            if seconds >= 60 {
                let m = Int(seconds) / 60
                let s = seconds.truncatingRemainder(dividingBy: 60)
                text = String(format: "%d:%05.2f", m, s)
            } else {
                text = String(format: "%.2fs", seconds)
            }
            return String(format: tr("projects.deck.duration_format", "耗时 %@"), text)
        }
        static func exitTag(_ outcome: ProjectWatchOutcome) -> String {
            switch outcome {
            case .succeeded:
                return tr("projects.deck.exit_tag_ok", "exit 0")
            case .failed(let code):
                return String(format: tr("projects.deck.exit_tag_code_format", "exit %d"), code)
            case .signaled(let signal):
                return watchOutcomeSignaled(signal)
            case .unknown:
                return tr("projects.deck.exit_tag_ended", "ended")
            }
        }
        static func statusBadge(_ outcome: ProjectWatchOutcome) -> String {
            switch outcome {
            case .succeeded:
                return tr("projects.deck.status_badge_success", "成功")
            case .failed, .signaled:
                return tr("projects.deck.status_badge_failed", "失败")
            case .unknown:
                return tr("projects.deck.status_badge_ended", "已结束")
            }
        }
        static func endedTitleCommand(_ label: String) -> String {
            // 岛上标题只展示命令本身，不再追加「进程已结束」。
            label
        }
        static func moreItems(_ count: Int) -> String {
            String(format: tr("projects.deck.more_items_format", "另有 %d 项"), count)
        }
        static func processCount(_ count: Int) -> String {
            String(format: tr("projects.deck.process_count_format", "%d 个进程"), count)
        }
        static func ports(_ ports: [Int]) -> String {
            let text = ports.prefix(5).map(String.init).joined(separator: "、")
            return String(format: tr("projects.deck.ports_format", "端口 %@"), text)
        }
        static var unknownProcess: String { tr("projects.deck.unknown_process", "未知进程") }
        static var unknownContainer: String { tr("projects.deck.unknown_container", "未命名容器") }
        static var imageLabel: String { tr("projects.deck.image_label", "镜像") }
        static var rootsTitle: String { tr("projects.settings.roots_title", "项目扫描目录") }
        static var rootsIntro: String {
            tr(
                "projects.settings.roots_intro",
                "填写代码所在的父文件夹，例如 ~/project。Ridge 会识别其中的项目，并汇总相关进程与容器。"
            )
        }
        static var rootsEmpty: String {
            tr("projects.settings.roots_empty", "尚未添加目录。添加后才会扫描其中的项目。")
        }
        static var addRoot: String { tr("projects.settings.add_root", "添加目录") }
    }

    // MARK: - Shelf + Clipboard（控制台）

    enum Shelf {
        static var deckTitle: String { tr("shelf.deck.title", "货架与剪贴板") }
        static var shelfTitle: String { tr("shelf.title", "瞬时货架") }
        static var clipboardTitle: String { tr("shelf.clipboard.title", "剪贴板历史") }
        static var dropHint: String {
            tr("shelf.drop_hint", "拖至此处暂存")
        }
        static var dropHintDetail: String {
            tr("shelf.drop_hint_detail", "任意文件均可暂存 · 悬停即存")
        }
        static var dropRamBadge: String {
            tr("shelf.drop_ram_badge", "RAM 内存驻留 · 零磁盘磨损")
        }
        static var dropActiveHint: String {
            tr("shelf.drop_active_hint", "释放即可暂存入舱")
        }
        static var dropActiveDetail: String {
            tr("shelf.drop_active_detail", "已识别拖拽对象 · 准备自动就绪")
        }
        static var dropMore: String { tr("shelf.drop_more", "继续拖入可追加") }
        static var kindFile: String { tr("shelf.kind.file", "文件") }
        static var kindFolder: String { tr("shelf.kind.folder", "文件夹") }
        static var kindDocument: String { tr("shelf.kind.document", "文档") }
        static var kindImage: String { tr("shelf.kind.image", "图片") }
        static var kindVideo: String { tr("shelf.kind.video", "视频") }
        static var kindAudio: String { tr("shelf.kind.audio", "音频") }
        static var kindSource: String { tr("shelf.kind.source", "源码") }
        static var kindArchive: String { tr("shelf.kind.archive", "压缩归档") }
        static var kindVector: String { tr("shelf.kind.vector", "矢量素材") }
        static var showInFinder: String { tr("shelf.show_in_finder", "在 Finder 中显示") }
        static var clearShelf: String { tr("shelf.clear", "清空货架") }
        static var clearClipboard: String { tr("shelf.clipboard.clear", "清空历史") }
        static var removeItem: String { tr("shelf.remove_item", "移出货架") }
        static var clipboardEmpty: String {
            tr("shelf.clipboard.empty", "复制文字、链接、颜色或截图后会出现在这里")
        }
        static var clipboardSearchPlaceholder: String {
            tr("shelf.clipboard.search_placeholder", "搜索")
        }
        static var colorPickHelp: String {
            tr("shelf.clipboard.color_pick_help", "屏幕取色：点选像素，复制为色值")
        }
        /// 取色引导无障碍 / 旧文案兜底。
        static var colorPickFirstTip: String {
            tr("shelf.clipboard.color_pick_first_tip", "左键取色 · Esc 取消")
        }
        static var colorPickTipLeft: String {
            tr("shelf.clipboard.color_pick_tip_left", "左键取色")
        }
        static var colorPickTipEsc: String {
            tr("shelf.clipboard.color_pick_tip_esc", "Esc 取消")
        }
        static var previewStageTitle: String {
            tr("shelf.preview.stage_title", "岛上预览")
        }
        static var previewStageShelf: String {
            tr("shelf.preview.stage_shelf", "货架")
        }
        static var previewStageShelfBadge: String {
            tr("shelf.preview.stage_shelf_badge", "主面板")
        }
        static var previewStageColorPick: String {
            tr("shelf.preview.stage_color_pick", "取色")
        }
        static var previewStageColorPickBadge: String {
            tr("shelf.preview.stage_color_pick_badge", "引导")
        }
        static var previewStageCopied: String {
            tr("shelf.preview.stage_copied", "已复制")
        }
        static var previewStageCopiedBadge: String {
            tr("shelf.preview.stage_copied_badge", "提示")
        }
        static var copiedNoticeToggle: String {
            tr("shelf.copied_notice.toggle", "复制后提示")
        }
        static var copiedNoticeToggleSubtitle: String {
            tr("shelf.copied_notice.toggle_subtitle", "复制成功时在灵动岛显示「已复制」")
        }
        static func colorPickDone(_ hex: String) -> String {
            String(
                format: String(
                    localized: "shelf.clipboard.color_pick_done",
                    defaultValue: "已复制 %@",
                    bundle: .main
                ),
                locale: .current,
                hex
            )
        }
        static var colorPickNeedScreenCapture: String {
            tr(
                "shelf.clipboard.color_pick_need_screen_capture",
                "屏幕取色需要「屏幕录制」权限，请在系统设置中允许 Ridge"
            )
        }
        static var ocrHelp: String {
            tr("shelf.clipboard.ocr_help", "屏幕取词：框选后只识别文字并复制，图案不会进剪贴板")
        }
        static func ocrDone(_ preview: String) -> String {
            String(
                format: String(
                    localized: "shelf.clipboard.ocr_done",
                    defaultValue: "已复制「%@」",
                    bundle: .main
                ),
                locale: .current,
                preview
            )
        }
        static var ocrDragHint: String {
            tr("shelf.clipboard.ocr_drag_hint", "拖拽框选文字 · Esc 取消")
        }
        static var ocrNeedScreenCapture: String {
            tr(
                "shelf.clipboard.ocr_need_screen_capture",
                "屏幕取词需要「屏幕录制」权限，请在系统设置中允许 Ridge"
            )
        }
        static var ocrEmpty: String {
            tr("shelf.clipboard.ocr_empty", "选区内未识别到文字")
        }
        static var ocrCaptureFailed: String {
            tr("shelf.clipboard.ocr_capture_failed", "截取选区失败，请重试")
        }
        static var ocrFailed: String {
            tr("shelf.clipboard.ocr_failed", "文字识别失败，请重试")
        }
        static var clipboardSearchClear: String {
            tr("shelf.clipboard.search_clear", "清除搜索")
        }
        static var clipboardSearchEmpty: String {
            tr("shelf.clipboard.search_empty", "无匹配内容")
        }
        static var clipboardImagePreview: String { tr("shelf.clipboard.image_preview", "图片") }
        static var previewFilePDF: String { tr("shelf.preview.file_pdf", "设计规范.pdf") }
        static var previewFileFolder: String { tr("shelf.preview.file_folder", "Assets") }
        static var previewFilePNG: String { tr("shelf.preview.file_png", "封面草稿.png") }
        static var previewClipText: String {
            tr("shelf.preview.clip_text", "下周评审改到周四 15:00")
        }
        static var previewClipLink: String {
            tr("shelf.preview.clip_link", "https://github.com/ridge/app")
        }
        static var previewClipColor: String { tr("shelf.preview.clip_color", "#0071E3") }
        static var previewClipTimeRecent: String { tr("shelf.preview.clip_time_recent", "2 分钟前") }
        static var previewClipTimeMid: String { tr("shelf.preview.clip_time_mid", "5 分钟前") }
        static var previewClipTimeOlder: String { tr("shelf.preview.clip_time_older", "12 分钟前") }
        static var copied: String { tr("shelf.copied", "已复制") }
        static var justCopied: String { tr("shelf.just_copied", "● 刚刚复制") }

        /// 任意复制上岛短提示。
        static func copiedNotice(for item: ClipboardHistoryItem) -> String {
            let preview = clippedPreview(item.preview, limit: 28)
            switch item.category {
            case .color:
                return colorPickDone(item.preview)
            case .link:
                return String(
                    format: String(
                        localized: "shelf.clipboard.copied_link",
                        defaultValue: "已复制链接 %@",
                        bundle: .main
                    ),
                    locale: .current,
                    preview
                )
            case .image:
                return tr("shelf.clipboard.copied_image", "已复制图片")
            case .screenshot:
                return tr("shelf.clipboard.copied_screenshot", "已复制截图")
            case .text, .all:
                return String(
                    format: String(
                        localized: "shelf.clipboard.copied_text",
                        defaultValue: "已复制「%@」",
                        bundle: .main
                    ),
                    locale: .current,
                    preview
                )
            }
        }

        private static func clippedPreview(_ raw: String, limit: Int) -> String {
            let trimmed = raw
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > limit else { return trimmed }
            return String(trimmed.prefix(limit)) + "…"
        }
        static var pasteDirect: String { tr("shelf.paste_direct", "直贴") }
        static var copyAgain: String { tr("shelf.copy_again", "再次复制") }
        static var pin: String { tr("shelf.pin", "置顶") }
        static var unpin: String { tr("shelf.unpin", "取消置顶") }

        static var tabAll: String { tr("shelf.tab.all", "全部") }
        static var tabText: String { tr("shelf.tab.text", "文本") }
        static var tabLink: String { tr("shelf.tab.link", "链接") }
        static var tabColor: String { tr("shelf.tab.color", "颜色") }
        static var tabImage: String { tr("shelf.tab.image", "图片") }
        static var tabScreenshot: String { tr("shelf.tab.screenshot", "截图") }
    }

    // MARK: - Meeting

    enum Meeting {
        static var widgetName: String { tr("meeting.widget.name", "下一场会议") }
        static var widgetSummary: String {
            tr("meeting.widget.summary", "下一场会议倒计时，到点一键入会")
        }

        static var calendarAccess: String { tr("meeting.calendar.access", "系统日历访问权限") }
        static var calendarAuthorized: String { tr("meeting.calendar.authorized", "已授权") }
        static var calendarAllow: String { tr("meeting.calendar.allow", "允许访问系统日历") }
        static var calendarDesc: String {
            tr(
                "meeting.calendar.desc",
                "用于读取本地日历、iCloud、Exchange 与同步会议日程"
            )
        }
        static var calendarDeniedDesc: String {
            tr("meeting.calendar.denied_desc", "日历权限未开启，请在系统设置中允许 Ridge 访问")
        }
        static var calendarDeniedShort: String { tr("meeting.calendar.denied_short", "未授予日历权限") }
        static var calendarNeedAuth: String { tr("meeting.calendar.need_auth", "需要日历权限") }
        static var calendarRequestFailed: String {
            tr("meeting.calendar.request_failed", "无法请求日历权限")
        }

        static var leadTitle: String { tr("meeting.lead.title", "提前提醒时间") }
        static var leadSubtitle: String {
            tr("meeting.lead.subtitle", "会议开始前在灵动岛显示入会按钮")
        }
        static func leadBadge(_ minutes: Int) -> String {
            String(format: tr("meeting.lead.badge_format", "提前 %d 分钟"), minutes)
        }
        static func minutes(_ n: Int) -> String {
            String(format: tr("meeting.lead.minutes_format", "%d 分钟"), n)
        }
        static func minutesRecommended(_ n: Int) -> String {
            String(format: tr("meeting.lead.minutes_recommended_format", "%d 分钟 (推荐)"), n)
        }

        static var platformsTitle: String { tr("meeting.platforms.title", "支持的会议平台") }
        static var platformsSubtitle: String {
            tr("meeting.platforms.subtitle", "自动从日程详情中识别入会链接，轻点即可调起客户端")
        }
        static var platformsAllSupported: String {
            tr("meeting.platforms.all_supported", "全部已支持")
        }

        static var customTitle: String { tr("meeting.custom.title", "自定义会议应用与链接") }
        static var customSubtitle: String {
            tr(
                "meeting.custom.subtitle",
                "添加会议名称与完整会议链接；将按域名识别后续日程，加入时打开日历中的链接。"
            )
        }
        static var customNamePlaceholder: String {
            tr("meeting.custom.name_placeholder", "会议名称（例如：Jitsi Meet）")
        }
        static var customLinkPlaceholder: String {
            tr("meeting.custom.link_placeholder", "完整会议链接（例如：meet.jit.si/…）")
        }
        static var customNameRequired: String {
            tr("meeting.custom.error_name_required", "请填写会议名称")
        }
        static var customBadLink: String {
            tr("meeting.custom.error_bad_link", "无法从链接解析域名，请检查格式")
        }
        static func customDomainInUse(domain: String, name: String) -> String {
            String(
                format: tr("meeting.custom.error_domain_in_use_format", "域名 %@ 已用于「%@」"),
                domain,
                name
            )
        }

        static var previewSampleTitle: String {
            tr("meeting.preview.sample_title", "周度产研协同同步会")
        }
        static func previewMinutesAhead(_ minutes: Int) -> String {
            String(format: tr("meeting.preview.minutes_ahead_format", "%d 分钟后开始"), minutes)
        }
        static var joinMeeting: String { tr("meeting.join", "进入会议") }
        static var joinA11y: String { tr("meeting.join_a11y", "加入会议") }
        static var joinShort: String { tr("meeting.join_short", "Join") }
        static var inProgress: String { tr("meeting.in_progress", "进行中") }
        static var ended: String { tr("meeting.ended", "已结束") }
        static var noUpcoming: String { tr("meeting.no_upcoming", "暂无即将开始的日程") }
        static var countdownTitle: String { tr("meeting.countdown_title", "会议倒计时") }
        static var untitled: String { tr("meeting.untitled", "未命名会议") }

        static var platformZoom: String { tr("meeting.platform.zoom", "Zoom") }
        static var platformGoogleMeet: String { tr("meeting.platform.google_meet", "Google Meet") }
        static var platformTeams: String { tr("meeting.platform.teams", "Microsoft Teams") }
        static var platformTeamsShort: String { tr("meeting.platform.teams_short", "MS Teams") }
        static var platformWebex: String { tr("meeting.platform.webex", "Webex") }
        static var platformFaceTime: String { tr("meeting.platform.facetime", "FaceTime") }
        static var platformTencent: String { tr("meeting.platform.tencent", "腾讯会议") }
        static var platformLark: String { tr("meeting.platform.lark", "飞书会议") }
        static var platformDingTalk: String { tr("meeting.platform.dingtalk", "钉钉会议") }
        static var platformCustom: String { tr("meeting.platform.custom", "自定义") }
        static var platformGeneric: String { tr("meeting.platform.generic", "浏览器") }
    }

    // MARK: - Info.plist usage（与 InfoPlist.xcstrings 对齐）

    enum InfoPlist {
        static var calendarsUsage: String {
            tr(
                "NSCalendarsUsageDescription",
                "Ridge 需要读取日历，以便在灵动岛显示即将开始的会议倒计时，并提供一键入会。"
            )
        }
        static var calendarsFullAccessUsage: String {
            tr(
                "NSCalendarsFullAccessUsageDescription",
                "Ridge 需要读取日历，以便在灵动岛显示即将开始的会议倒计时，并提供一键入会。日历数据仅在本机处理。"
            )
        }
        static var screenCaptureUsage: String {
            tr(
                "NSScreenCaptureUsageDescription",
                "Ridge 需要屏幕录制权限以通过系统音频接口调节其它 App 的音量；不会录制或保存屏幕画面。"
            )
        }
        static var bluetoothAlwaysUsage: String {
            tr(
                "NSBluetoothAlwaysUsageDescription",
                "Ridge 需要蓝牙权限以读取已连接耳机等设备的电量，并在控制台混音台中显示。"
            )
        }
    }

    // MARK: - Battery（控制台电量与外设）

    enum Battery {
        static var emptyTitle: String { tr("battery.empty.title", "暂无外设电量") }
        static var emptyHint: String {
            tr("battery.empty.hint", "连接带电量报告的蓝牙键盘、鼠标或耳机后将显示在此")
        }
        static var statusCharging: String { tr("battery.status.charging", "充电中") }
        static var statusCritical: String { tr("battery.status.critical", "电量过低") }
        static var statusHealthy: String { tr("battery.status.healthy", "电量充足") }
        static var statusModerate: String { tr("battery.status.moderate", "电量一般") }
        static var statusConnected: String { tr("battery.status.connected", "已连接") }
        static var statusUnknownBattery: String { tr("battery.status.unknown_battery", "电量不可用") }
        static var badgeCharging: String { tr("battery.badge.charging", "充电") }
        static var badgeNeedCharge: String { tr("battery.badge.need_charge", "需充电") }
        static var leftBud: String { tr("battery.bud.left", "左耳") }
        static var rightBud: String { tr("battery.bud.right", "右耳") }
        static var caseBud: String { tr("battery.bud.case", "耳机盒") }

        static var listeningOff: String { tr("battery.listening.off", "关闭") }
        static var listeningNoiseCancellation: String {
            tr("battery.listening.noise_cancellation", "降噪")
        }
        static var listeningTransparency: String {
            tr("battery.listening.transparency", "通透")
        }
        static var listeningAdaptive: String {
            tr("battery.listening.adaptive", "自适应")
        }

        static func listeningModeTitle(_ mode: BatteryListeningMode) -> String {
            switch mode {
            case .off: return listeningOff
            case .noiseCancellation: return listeningNoiseCancellation
            case .transparency: return listeningTransparency
            case .adaptive: return listeningAdaptive
            }
        }

        static var alertsTitle: String { tr("battery.alerts.title", "电量告警") }
        static var alertsIntro: String {
            tr(
                "battery.alerts.intro",
                "开启后可在灵动岛查看已连接外设电量。低电与满电经瞬时通知提示，约三秒后自动收起。"
            )
        }
        static var forceExpandTitle: String {
            tr("battery.alerts.force_expand_title", "严重低电量强制展开灵动岛")
        }
        static var forceExpandSubtitle: String {
            tr(
                "battery.alerts.force_expand_subtitle",
                "当任一外设电量低于设定阈值时，自动展开刘海进行视觉警告"
            )
        }
        static var lowAlertToggle: String { tr("battery.alerts.low_toggle", "低电量提醒") }
        static var lowThreshold: String { tr("battery.alerts.low_threshold", "低电量触发阈值") }
        static func lowThresholdHint(_ percent: Int) -> String {
            String(
                format: String(
                    localized: "battery.alerts.low_threshold_hint_format",
                    defaultValue: "电量 ≤ %d%% 且未在充电时提醒"
                ),
                percent
            )
        }
        static var fullAlertToggle: String {
            tr("battery.alerts.full_toggle", "充满电提醒（防止过充）")
        }
        static var fullAlertHint: String {
            tr(
                "battery.alerts.full_hint",
                "外设电量达到 100% 时弹出灵动岛横幅，提醒及时移除充电线缆以保护电池"
            )
        }
        static var snoozeHint: String {
            tr("battery.alerts.snooze_hint", "提示卡上「稍后提醒」：该设备低电免打扰 30 分钟")
        }
        static var tipSectionTitle: String {
            tr("battery.tip.section_title", "独立告警灵动岛展示")
        }
        static var tipSectionSubtitle: String {
            tr(
                "battery.tip.section_subtitle",
                "低电量告警与满电防过充小提示；约三秒后自动收起，悬停时保持展示"
            )
        }
        static var tipSampleMouse: String { tr("battery.tip.sample_mouse", "妙控鼠标 2") }
        static var tipSampleKeyboard: String { tr("battery.tip.sample_keyboard", "妙控键盘") }
        static func tipSampleLowDetail(_ threshold: Int) -> String {
            String(
                format: String(
                    localized: "battery.tip.sample_low_detail_format",
                    defaultValue: "已低于预设 %d%% 告警阈值"
                ),
                threshold
            )
        }
        static func tipSampleLowFooter(_ percent: Int) -> String {
            tipSampleLowDetail(percent)
        }
        static var tipSampleFullDetail: String {
            tr("battery.tip.sample_full_detail", "电池已充满 · 建议拔除充电线缆")
        }
        static var tipSampleFullFooter: String {
            tr("battery.tip.sample_full_footer", "已达满电状态")
        }
        static func tipLowBadge(_ percent: Int) -> String {
            String(
                format: String(
                    localized: "battery.tip.low_badge_format",
                    defaultValue: "%d%% 严重低电"
                ),
                percent
            )
        }
        static var tipFullBadge: String { tr("battery.tip.full_badge", "100% 已充满") }
        static var previewLowNotice: String { tr("battery.tip.preview_low", "预览低电提示") }
        static var previewFullNotice: String { tr("battery.tip.preview_full", "预览满电提示") }
        static var snoozeAction: String { tr("battery.tip.snooze_action", "稍后提醒") }

        static func lowNoticeTitle(_ name: String) -> String {
            String(
                format: String(
                    localized: "battery.notice.low_title_format",
                    defaultValue: "%@ 电量过低"
                ),
                name
            )
        }
        static func lowNoticeDetail(_ percent: Int, _ threshold: Int) -> String {
            // percent 保留入参，便于调用点不变；副标题只展示阈值，不做剩余时长估算。
            _ = percent
            return tipSampleLowDetail(threshold)
        }
        static func fullNoticeTitle(_ name: String) -> String {
            String(
                format: String(
                    localized: "battery.notice.full_title_format",
                    defaultValue: "%@ 已充满"
                ),
                name
            )
        }
        static var fullNoticeDetail: String {
            tr("battery.notice.full_detail", "电池已充满 · 建议拔除充电线缆")
        }
    }

    // MARK: - Island notice（隐性瞬时通知，不进库）

    enum IslandNotice {
        static var widgetName: String { tr("island_notice.widget.name", "岛内通知") }
        static var widgetSummary: String {
            tr("island_notice.widget.summary", "通用瞬时通知（如监视结束），约三秒后收起")
        }
        static var endedHeadline: String { tr("island_notice.ended.headline", "进程已结束") }
        static var endedSuccessHeadline: String {
            tr("island_notice.ended.success_headline", "执行成功")
        }
        static var endedFailedHeadline: String {
            tr("island_notice.ended.failed_headline", "执行失败")
        }
        static func headline(for outcome: ProjectWatchOutcome) -> String {
            switch outcome {
            case .succeeded: return endedSuccessHeadline
            case .failed, .signaled: return endedFailedHeadline
            case .unknown: return endedHeadline
            }
        }
        static func accessibilityLabel(_ notice: ProjectWatchEndedNotice) -> String {
            notice.message
        }
    }

    // MARK: - Resource monitor

    enum ResourceMonitor {
        static var pageTitle: String { tr("resource_monitor.page_title", "RAM 监控与进程树") }
        static var pageSubtitle: String {
            tr(
                "resource_monitor.page_subtitle",
                "按 App 折叠子进程 · 高压时经岛内瞬时通知提示"
            )
        }
        static var sampleInterval: String { tr("resource_monitor.sample_interval", "指标 2s · 进程树 6s") }
        static var liveDispatch: String { tr("resource_monitor.live_dispatch", "Live Dispatch: 60 FPS") }
        static var criticalOverload: String {
            tr("resource_monitor.critical_overload", "严重超标")
        }
        static var engineReady: String { tr("resource_monitor.engine_ready", "引擎就绪") }
        /// 岛内 / 设置页：同一动作、同一文案。
        static var muteAlert: String { tr("resource_monitor.mute_alert", "免打扰（30m）") }
        static var mutedBanner: String { tr("resource_monitor.muted_banner", "已免打扰 30 分钟") }
        static var requestPermission: String {
            tr("resource_monitor.request_permission", "申请权限")
        }
        static var permissionAccess: String {
            tr("resource_monitor.permission_access", "输入监控权限")
        }
        static var permissionAccessDesc: String {
            tr(
                "resource_monitor.permission_access_desc",
                "用于统计击键次数与专注活跃度"
            )
        }
        static var permissionGranted: String {
            tr("resource_monitor.permission_granted", "已授权")
        }
        static var permissionGrantedBanner: String {
            tr("resource_monitor.permission_granted_banner", "输入监控已授权，开始统计击键")
        }
        static var purgeButton: String { tr("resource_monitor.purge_button", "强制回收内存") }
        static var purgeShort: String { tr("resource_monitor.purge_short", "一键释放") }
        static var purging: String { tr("resource_monitor.purging", "正在尽力回收内存…") }
        static var purgeNoChange: String {
            tr("resource_monitor.purge_no_change", "已尝试回收，用量未见明显下降")
        }
        static var purgeFailed: String {
            tr("resource_monitor.purge_failed", "回收失败（可能需要更高权限）")
        }
        static func purgeDone(_ bytes: UInt64) -> String {
            String(
                format: String(localized: "resource_monitor.purge_done_format", defaultValue: "已尽力回收约 %@"),
                byteString(bytes)
            )
        }

        static var ramCard: String { tr("resource_monitor.ram_card", "物理 RAM 占用") }
        static var swapCard: String { tr("resource_monitor.swap_card", "交换分区 Swap") }
        static var cpuCard: String { tr("resource_monitor.cpu_card", "CPU 总负载") }
        static var keystrokeCard: String { tr("resource_monitor.keystroke_card", "今日打字击键") }
        static var switchCard: String { tr("resource_monitor.switch_card", "窗口焦点切换") }
        static var keysUnit: String { tr("resource_monitor.keys_unit", "Keys") }
        static var switchesUnit: String { tr("resource_monitor.switches_unit", "次") }
        /// 焦点切换卡片右上角：标明主数字为今日累计。
        static var todayCumulative: String {
            tr("resource_monitor.today_cumulative", "今日累计")
        }
        static var highPressure: String { tr("resource_monitor.high_pressure", "内存高压") }
        static func thresholdHint(_ percent: Int) -> String {
            String(
                format: String(localized: "resource_monitor.threshold_hint_format", defaultValue: "危险阈值: %d%%"),
                percent
            )
        }
        static var swapPressureLow: String { tr("resource_monitor.swap_pressure_low", "交换压力较低") }
        /// Swap 落在 SSD 上，脚注按交换用量映射为 SSD 读写压力。
        static var ssdPressureLow: String {
            tr("resource_monitor.ssd_pressure_low", "SSD 读写压力: 较低")
        }
        static var ssdPressureMid: String {
            tr("resource_monitor.ssd_pressure_mid", "SSD 读写压力: 中等")
        }
        static var ssdPressureHigh: String {
            tr("resource_monitor.ssd_pressure_high", "SSD 读写压力: 偏高")
        }
        static func performanceCores(_ n: Int) -> String {
            String(
                format: String(localized: "resource_monitor.perf_cores_format", defaultValue: "%d核性能核心"),
                n
            )
        }
        static func chipTemp(_ chip: String, _ celsius: Double) -> String {
            String(
                format: String(
                    localized: "resource_monitor.chip_temp_format",
                    defaultValue: "%@ (%.0f℃)"
                ),
                chip,
                celsius
            )
        }
        static var keystrokePeakPlaceholder: String {
            tr("resource_monitor.keystroke_peak_placeholder", "峰值时段: —")
        }
        static func keystrokePeak(_ range: String) -> String {
            String(
                format: String(
                    localized: "resource_monitor.keystroke_peak_format",
                    defaultValue: "峰值时段: %@"
                ),
                range
            )
        }
        /// 焦点切换：0～80 良好，81～180 中等，>180 高频（次/小时）。
        static var focusLevelGood: String {
            tr("resource_monitor.focus_level_good", "专注良好")
        }
        static var focusLevelMid: String {
            tr("resource_monitor.focus_level_mid", "专注中等")
        }
        static var focusLevelBusy: String {
            tr("resource_monitor.focus_level_busy", "高频切换")
        }
        static func focusSwitchFootnote(_ perHour: Int, _ level: String) -> String {
            String(
                format: String(
                    localized: "resource_monitor.focus_switch_footnote_format",
                    defaultValue: "平均每小时 %d 次 · %@"
                ),
                perHour,
                level
            )
        }
        static var topAppsTitle: String { tr("resource_monitor.top_apps_title", "Top 5 吃 RAM 巨无霸") }
        /// 收起 Top App 下已展开的子进程树。
        static var collapseHierarchy: String {
            tr("resource_monitor.collapse_hierarchy", "折叠层级视图")
        }
        static var sortByRSS: String {
            tr("resource_monitor.sort_by_rss", "排序: 物理内存占用 (RSS)")
        }
        static func childCount(_ n: Int) -> String {
            String(
                format: String(localized: "resource_monitor.child_count_format", defaultValue: "%d 个子进程"),
                n
            )
        }
        static var kill: String { tr("resource_monitor.kill", "结束") }
        static var killNotFound: String { tr("resource_monitor.kill_not_found", "进程已不存在") }
        static var killProtected: String {
            tr("resource_monitor.kill_protected", "受保护进程，无法结束")
        }
        static var killPermissionDenied: String {
            tr("resource_monitor.kill_permission_denied", "权限不足，无法结束该进程")
        }
        static func killOther(_ detail: String) -> String {
            String(
                format: String(localized: "resource_monitor.kill_other_format", defaultValue: "结束失败：%@"),
                detail
            )
        }
        static func killedBanner(_ name: String) -> String {
            String(
                format: String(localized: "resource_monitor.killed_banner_format", defaultValue: "已结束 %@"),
                name
            )
        }
        static var unknownApp: String { tr("resource_monitor.unknown_app", "未知应用") }
        static var emptyTop: String { tr("resource_monitor.empty_top", "暂无第三方 App 占用数据") }
        static var behaviorTitle: String { tr("resource_monitor.behavior_title", "24 小时专注时间线") }
        static var behaviorHint: String {
            tr(
                "resource_monitor.behavior_hint",
                "全天候无感记录应用驻留专注度、人机交互空闲节拍与击键脉冲。"
            )
        }
        static var focusDistribution: String {
            tr("resource_monitor.focus_distribution", "24h 工作专注/空闲时序带")
        }
        static func focusWindowRange(_ start: Date) -> String {
            String(
                format: String(
                    localized: "resource_monitor.focus_window_range_format",
                    defaultValue: "%@ - 现在"
                ),
                focusClock(start)
            )
        }
        static var focusTickNow: String { tr("resource_monitor.focus_tick_now", "现在") }
        static func focusClock(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        static var focusRankTitle: String {
            tr("resource_monitor.focus_rank_title", "应用聚焦驻留排行")
        }
        static var focusRankBadge: String {
            tr("resource_monitor.focus_rank_badge", "系统级真实事件")
        }
        static var focusTodayTotalLabel: String {
            tr("resource_monitor.focus_today_total_label", "今日专注累计: ")
        }
        static func focusSharePercent(_ percent: Double) -> String {
            String(
                format: String(localized: "resource_monitor.focus_share_format", defaultValue: "%.0f%% 驻留"),
                percent
            )
        }
        static var focusMetricKeys: String { tr("resource_monitor.focus_metric_keys", "击键") }
        static var focusMetricSwitches: String { tr("resource_monitor.focus_metric_switches", "切换") }
        static var focusMetricAverage: String { tr("resource_monitor.focus_metric_average", "平均单次") }
        static var focusMetricLongest: String { tr("resource_monitor.focus_metric_longest", "最长连续") }
        static func focusKeystrokeCount(_ n: Int) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            let body = f.string(from: NSNumber(value: n)) ?? "\(n)"
            return String(
                format: String(localized: "resource_monitor.focus_keys_count_format", defaultValue: "%@ 次"),
                body
            )
        }
        static func focusSwitchCount(_ n: Int) -> String {
            String(
                format: String(localized: "resource_monitor.focus_switch_count_format", defaultValue: "%d 次"),
                n
            )
        }
        /// 平均单次：分钟一位小数，如 `5.0 分`。
        static func focusAverageMinutes(_ seconds: TimeInterval) -> String {
            let minutes = max(0, seconds / 60.0)
            return String(
                format: String(localized: "resource_monitor.focus_avg_min_format", defaultValue: "%.1f 分"),
                minutes
            )
        }
        static var focusCategoryBrowser: String {
            tr("resource_monitor.focus_category_browser", "网页浏览器")
        }
        static var focusCategoryIDE: String {
            tr("resource_monitor.focus_category_ide", "开发工具")
        }
        static var focusCategoryTerminal: String {
            tr("resource_monitor.focus_category_terminal", "终端命令行")
        }
        static var focusCategoryOther: String {
            tr("resource_monitor.focus_category_other", "其他应用")
        }
        static var focusEmptyRank: String {
            tr("resource_monitor.focus_empty_rank", "今日尚无应用驻留记录")
        }
        static var heatmapTitle: String {
            tr("resource_monitor.heatmap_title", "本年研发击键热力")
        }
        /// 热力格悬停：`11月3日`。
        static func heatmapDayLabel(month: Int, day: Int) -> String {
            String(
                format: String(localized: "resource_monitor.heatmap_day_format", defaultValue: "%d月%d日"),
                month,
                day
            )
        }
        /// 年累计紧凑数：≥1B → `1.2B`；≥1M → `4.2M`（含远超百万）；≥1K → `12.3K`；否则原数。
        static func yearKeys(_ n: Int) -> String {
            let compact: String
            if n >= 1_000_000_000 {
                compact = String(format: "%.1fB", Double(n) / 1_000_000_000.0)
            } else if n >= 1_000_000 {
                compact = String(format: "%.1fM", Double(n) / 1_000_000.0)
            } else if n >= 1_000 {
                compact = String(format: "%.1fK", Double(n) / 1_000.0)
            } else {
                compact = "\(n)"
            }
            return String(
                format: String(localized: "resource_monitor.year_keys_format", defaultValue: "年累计 %@ 键"),
                compact
            )
        }
        static func activeStreak(_ days: Int) -> String {
            String(
                format: String(localized: "resource_monitor.active_streak_format", defaultValue: "连续活跃: %d 天"),
                days
            )
        }
        static var heatLow: String { tr("resource_monitor.heat_low", "低活跃") }
        static var heatHigh: String { tr("resource_monitor.heat_high", "高负荷") }
        static var alertPolicyTitle: String {
            tr("resource_monitor.alert_policy_title", "自动化告警策略：RAM 过载")
        }
        static var alertActive: String { tr("resource_monitor.alert_active", "已开启") }
        static var alertInactive: String { tr("resource_monitor.alert_inactive", "已关闭") }
        static var alertPolicyBeforeThreshold: String {
            tr("resource_monitor.alert_policy_before_threshold", "当 RAM 超过")
        }
        static func alertPolicyAfterThreshold(_ gb: Double) -> String {
            String(
                format: String(
                    localized: "resource_monitor.alert_policy_after_threshold_format",
                    defaultValue: "%% 时，经岛内瞬时通知提示，并点名占用最高的 App（参考单 App %.0f GB）。"
                ),
                gb
            )
        }
        static var ramThresholdField: String {
            tr("resource_monitor.ram_threshold_field", "RAM 告警阈值")
        }
        static var alertToggle: String { tr("resource_monitor.alert_toggle", "启用自动化告警") }
        static var keystrokeNeedPermission: String {
            tr("resource_monitor.keystroke_need_permission", "未获输入监控权限，击键暂为 0")
        }
        static func noticeTitle(_ usedBytes: UInt64) -> String {
            String(
                format: String(localized: "resource_monitor.notice_title_format", defaultValue: "RAM 警告: %@"),
                byteString(usedBytes)
            )
        }
        static func noticeSubtitle(_ app: String, _ bytes: UInt64) -> String {
            String(
                format: String(
                    localized: "resource_monitor.notice_subtitle_format",
                    defaultValue: "%@ 占用 %@"
                ),
                app,
                byteString(bytes)
            )
        }
        static func processesMonitored(_ monitored: Int, _ kernelHosted: Int) -> String {
            String(
                format: String(
                    localized: "resource_monitor.processes_monitored_format",
                    defaultValue: "已监控进程总量: %d / 系统内核托管 %d"
                ),
                monitored,
                kernelHosted
            )
        }
        /// 焦点驻留展示：按分钟四舍五入；有驻留但不足 0.5 分钟仍显示 1m，避免长期「0m」。
        static func durationHours(_ seconds: TimeInterval) -> String {
            guard seconds > 0 else {
                return String(
                    format: String(localized: "resource_monitor.duration_m_format", defaultValue: "%dm"),
                    0
                )
            }
            var minutes = Int((seconds / 60.0).rounded())
            if minutes == 0 { minutes = 1 }
            let h = minutes / 60
            let m = minutes % 60
            if h > 0 {
                return String(
                    format: String(localized: "resource_monitor.duration_hm_format", defaultValue: "%dh %dm"),
                    h,
                    m
                )
            }
            return String(
                format: String(localized: "resource_monitor.duration_m_format", defaultValue: "%dm"),
                m
            )
        }

        private static func byteString(_ bytes: UInt64) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
        }
    }

    // MARK: - Focus Timer（专注计时）

    enum FocusTimer {
        static var widgetName: String { tr("focus_timer.widget.name", "专注计时") }
        static var widgetSummary: String {
            tr("focus_timer.widget.summary", "选时起钟、计时待命与加时收拢，常驻灵动岛")
        }

        static var phaseStandby: String { tr("focus_timer.phase.standby", "标准待命态") }
        static var phasePicking: String { tr("focus_timer.phase.picking", "选时起钟态") }
        static var phaseRunning: String { tr("focus_timer.phase.running", "计时进行中") }
        static var phaseOvertime: String { tr("focus_timer.phase.overtime", "顺延加时中") }
        static var phaseCompleted: String { tr("focus_timer.phase.completed", "终局收拢态") }
        static var tabBadgeCustom: String { tr("focus_timer.tab.badge_custom", "自选") }
        static var tabBadgeSummary: String { tr("focus_timer.tab.badge_summary", "总结") }

        static var focusing: String { tr("focus_timer.focusing", "专注中") }
        static var overtimeBadge: String { tr("focus_timer.overtime_badge", "加时中") }
        static var pickingTitle: String {
            tr("focus_timer.picking.title", "设定专注时长并起钟")
        }
        static var pickingHint: String {
            tr("focus_timer.picking.hint", "快捷预设 或 自选分钟")
        }
        static var start: String { tr("focus_timer.start", "开始计时") }
        static var remaining: String { tr("focus_timer.remaining", "剩余") }
        static var finishEarly: String { tr("focus_timer.finish_early", "结束") }
        static var finishDone: String { tr("focus_timer.finish_done", "完成收工") }
        /// 终局按钮：把用户填入的标题写回已入库记录。
        static var saveRecord: String { tr("focus_timer.save_record", "完成命名") }
        static var completedTitle: String {
            tr("focus_timer.completed.title", "计时完成")
        }
        static var autoArchivedBadge: String {
            tr("focus_timer.auto_archived_badge", "已自动归档")
        }
        static var notePlaceholder: String {
            tr("focus_timer.note_placeholder", "记录已入库，点击添加标题（可选）")
        }
        static var defaultTimeNameHint: String {
            tr("focus_timer.default_time_name_hint", "默认按时间命名")
        }
        static var customSessionTitle: String {
            tr("focus_timer.custom_session_title", "自定义专注")
        }
        static var previewNote: String {
            tr("focus_timer.preview_note", "排查异步死锁并重构")
        }

        static func presetChip(minutes: Int, title: String) -> String {
            String(format: tr("focus_timer.preset_chip_format", "%dm %@"), minutes, title)
        }
        static func presetMinutesChip(_ minutes: Int) -> String {
            String(format: tr("focus_timer.preset_minutes_chip_format", "%dm"), minutes)
        }
        static var minutesAbbrev: String {
            tr("focus_timer.minutes_abbrev", "m")
        }
        static func plannedLabel(_ minutes: Int) -> String {
            String(format: tr("focus_timer.planned_format", "总设 %dm"), minutes)
        }
        static func elapsedLabel(_ clock: String) -> String {
            String(format: tr("focus_timer.elapsed_format", "已过 %@"), clock)
        }
        static func extendChip(_ minutes: Int) -> String {
            String(format: tr("focus_timer.extend_chip_format", "+%dm"), minutes)
        }
        static func extendAgain(_ minutes: Int) -> String {
            String(format: tr("focus_timer.extend_again_format", "微调 +%dm"), minutes)
        }
        static func overtimeAdded(_ minutes: Int) -> String {
            String(format: tr("focus_timer.overtime_added_format", "+%dm 顺延"), minutes)
        }
        static func totalPlanned(_ minutes: Int) -> String {
            String(format: tr("focus_timer.total_planned_format", "总计 %dm"), minutes)
        }
        static func baseMinutes(_ minutes: Int) -> String {
            String(format: tr("focus_timer.base_minutes_format", "基础 %dm"), minutes)
        }
        static func overtimeMinutesLabel(_ minutes: Int) -> String {
            String(format: tr("focus_timer.overtime_minutes_format", "顺延 %dm"), minutes)
        }
        static func totalFocus(_ minutes: Int) -> String {
            String(format: tr("focus_timer.total_focus_format", "总专注 %dm"), minutes)
        }

        static var presetSprint: String { tr("focus_timer.preset.sprint", "短时冲刺") }
        static var presetSprintHint: String { tr("focus_timer.preset.sprint_hint", "快速同步与收口") }
        static var presetTomato: String { tr("focus_timer.preset.tomato", "标准专注") }
        static var presetTomatoHint: String { tr("focus_timer.preset.tomato_hint", "半小时专注块") }
        static var presetDeep: String { tr("focus_timer.preset.deep", "深度专注") }
        static var presetDeepHint: String { tr("focus_timer.preset.deep_hint", "沉浸编码攻关") }
        static var presetLong: String { tr("focus_timer.preset.long", "长跑冲刺") }
        static var presetLongHint: String { tr("focus_timer.preset.long_hint", "大块心流时段") }
        static var presetBreak: String { tr("focus_timer.preset.break", "短息调养") }
        static var presetBreakHint: String { tr("focus_timer.preset.break_hint", "远眺补水拉伸") }

        static var overviewTitle: String {
            tr("focus_timer.overview.title", "今日专注概览")
        }
        static var overviewTodayStats: String {
            tr("focus_timer.overview.today_stats", "今日统计")
        }
        static var overviewTodayTotal: String {
            tr("focus_timer.overview.today_total", "今日累计")
        }
        static var overviewTimesUnit: String {
            tr("focus_timer.overview.times_unit", "次")
        }
        static var overviewFocusHours: String {
            tr("focus_timer.overview.focus_hours", "今日专注工时")
        }
        static var overviewMinutesUnit: String {
            tr("focus_timer.overview.minutes_unit", "分钟")
        }
        static var overviewFocusHint: String {
            tr("focus_timer.overview.focus_hint", "专注时长核心聚焦")
        }
        static var overviewOvertimeSprint: String {
            tr("focus_timer.overview.overtime_sprint", "顺延冲刺")
        }
        static var overviewFooterHint: String {
            tr("focus_timer.overview.footer_hint", "专注数据随计时实时更新")
        }
        static var overviewFocusMode: String {
            tr("focus_timer.overview.focus_mode", "专注模式")
        }
        static var presetsResetDefaults: String {
            tr("focus_timer.presets.reset_defaults", "重置默认")
        }

        static var colPreset: String { tr("focus_timer.col.preset", "预设标准倒计时") }
        static var colCustom: String { tr("focus_timer.col.custom", "自定义自由倒计时") }
        static var colOvertime: String { tr("focus_timer.col.overtime", "深度加时与顺延冲刺") }
        static func todayCompletedCount(_ count: Int) -> String {
            String(format: tr("focus_timer.col.today_completed_format", "今日已完成 %d 次"), count)
        }
        /// 三栏角标（对齐稿面：N 轮记录 / 自由输入 N 轮 / N 轮顺延）。
        static func colPresetBadge(_ count: Int) -> String {
            String(format: tr("focus_timer.col.preset_badge_format", "%d 轮记录"), count)
        }
        static func colCustomBadge(_ count: Int) -> String {
            String(format: tr("focus_timer.col.custom_badge_format", "自由输入 %d 轮"), count)
        }
        static func colOvertimeBadge(_ count: Int) -> String {
            String(format: tr("focus_timer.col.overtime_badge_format", "%d 轮顺延"), count)
        }
        static var historyEmptyPresetTitle: String {
            tr("focus_timer.history_empty.preset_title", "今日暂无预设倒计时记录")
        }
        static var historyEmptyPresetHint: String {
            tr("focus_timer.history_empty.preset_hint", "开始倒计时后自动在此归档")
        }
        static var historyEmptyCustomTitle: String {
            tr("focus_timer.history_empty.custom_title", "今日暂无自由倒计时记录")
        }
        static var historyEmptyCustomHint: String {
            tr("focus_timer.history_empty.custom_hint", "单次自定义时长记录将展示在此")
        }
        static var historyEmptyOvertimeTitle: String {
            tr("focus_timer.history_empty.overtime_title", "今日尚未产生顺延加时")
        }
        static var historyEmptyOvertimeHint: String {
            tr("focus_timer.history_empty.overtime_hint", "计时结束后的专注顺延时长将在此统计")
        }
        static var onTime: String { tr("focus_timer.on_time", "准时扣响") }
        static var customPrecision: String {
            tr("focus_timer.custom_precision", "自定精度 ±0s")
        }
        static func achievePercent(_ value: Int) -> String {
            String(format: tr("focus_timer.achieve_percent_format", "达成 %d%%"), value)
        }
        /// 看板左上角：用户开钟时点选的计划时长（如 05m / 25m）。
        static func badgePlannedMinutes(_ minutes: Int) -> String {
            String(format: tr("focus_timer.badge.planned_minutes_format", "%02dm"), minutes)
        }
        /// 顺延栏左下角加时（如 +10m）。
        static func overtimePlusMinutes(_ minutes: Int) -> String {
            String(format: tr("focus_timer.overtime_plus_format", "+%dm"), minutes)
        }
        static func badgeTomato(_ n: Int) -> String {
            String(format: tr("focus_timer.badge.tomato_format", "专注 #%02d"), n)
        }
        static func badgeBreak(_ n: Int) -> String {
            String(format: tr("focus_timer.badge.break_format", "短息 #%02d"), n)
        }
        static func badgeLong(_ n: Int) -> String {
            String(format: tr("focus_timer.badge.long_format", "长跑 #%02d"), n)
        }
        static func badgeCustom(_ minutes: Int) -> String {
            String(format: tr("focus_timer.badge.custom_format", "键入 %dm"), minutes)
        }
        static func badgeOvertime(_ minutes: Int) -> String {
            String(format: tr("focus_timer.badge.overtime_format", "+%dm 顺延"), minutes)
        }
        static func overtimeBreakdown(planned: Int, overtime: Int) -> String {
            String(
                format: tr("focus_timer.overtime_breakdown_format", "原定 %dm + 顺延 %dm"),
                planned,
                overtime
            )
        }
        static func baseline(_ minutes: Int) -> String {
            String(format: tr("focus_timer.baseline_format", "基准线 (%dm)"), minutes)
        }
        static func flowExtend(_ minutes: Int) -> String {
            String(format: tr("focus_timer.flow_extend_format", "+%dm (心流延伸)"), minutes)
        }
        static var untitled: String { tr("focus_timer.untitled", "未命名专注") }
        static var fillTitleAction: String {
            tr("focus_timer.fill_title_action", "+ 补填事项名称")
        }
        static var fillTitlePlaceholder: String {
            tr("focus_timer.fill_title_placeholder", "输入事项名称…")
        }
        static var saveTitle: String { tr("focus_timer.save_title", "保存") }
        static var statusPendingFill: String {
            tr("focus_timer.status_pending_fill", "状态 A 待填")
        }
        static var endedEarlyStatus: String {
            tr("focus_timer.ended_early_status", "提前结束")
        }
        static var finishedOnTimeStatus: String {
            tr("focus_timer.finished_on_time_status", "准时结束")
        }
        static var statusEditing: String {
            tr("focus_timer.status_editing", "状态 B: 输入保存中")
        }
        static var quickTagReview: String { tr("focus_timer.quick_tag.review", "需求评审") }
        static var quickTagBug: String { tr("focus_timer.quick_tag.bug", "排查Bug") }
        static var quickTagDeep: String { tr("focus_timer.quick_tag.deep", "技术攻关") }
        static var escToClose: String {
            tr("focus_timer.esc_to_close", "支持 Esc 键原位关闭")
        }
        static func timeRange(_ start: String, _ end: String) -> String {
            String(format: tr("focus_timer.time_range_format", "开始: %@ - 结束: %@"), start, end)
        }
        static var presetsTitle: String {
            tr("focus_timer.presets.title", "预设标准倒计时配置")
        }
        static var presetsSubtitle: String {
            tr("focus_timer.presets.subtitle", "维护灵动岛快捷选择与标准轮次的默认档位")
        }
        static func presetsSlotCount(_ count: Int) -> String {
            String(format: tr("focus_timer.presets.slot_count_format", "%d 档位"), count)
        }
        static var extendStep: String {
            tr("focus_timer.extend_step", "每次加时步长")
        }
        static var extendStepShort: String {
            tr("focus_timer.extend_step_short", "顺延步长")
        }
        static func extendStepChip(_ minutes: Int) -> String {
            String(format: tr("focus_timer.extend_step_chip_format", "+%dm"), minutes)
        }
        static func presetAdjustMinus(_ step: Int) -> String {
            String(format: tr("focus_timer.preset_adjust_minus_format", "-%d"), step)
        }
        static func presetAdjustPlus(_ step: Int) -> String {
            String(format: tr("focus_timer.preset_adjust_plus_format", "+%d"), step)
        }
    }

    // MARK: - Helpers

    private static func tr(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue)
    }
}
