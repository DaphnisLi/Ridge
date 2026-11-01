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
        static var minuteUnit: String { tr("common.minute_unit", "分") }
    }

    // MARK: - Settings shell

    enum Settings {
        static var island: String { tr("settings.section.island", "灵动岛") }
        static var controlDeck: String { tr("settings.section.control_deck", "控制台") }
        static var widgets: String { tr("settings.section.widgets", "小组件") }

        static var presetTheme: String { tr("settings.island.preset_theme", "预设主题") }
        static var expandedWidth: String { tr("settings.island.expanded_width", "展开后宽度") }
        static var widthNarrow: String { tr("settings.island.width_narrow", "窄") }
        static var widthWide: String { tr("settings.island.width_wide", "宽") }
        static var bottomCorner: String { tr("settings.island.bottom_corner", "下圆角") }
        static var cornerSquare: String { tr("settings.island.corner_square", "直角") }
        static var cornerRound: String { tr("settings.island.corner_round", "圆润") }
        static var animationSpeed: String { tr("settings.island.animation_speed", "展开动画速度") }
        static var speedSlow: String { tr("settings.island.speed_slow", "慢") }
        static var speedFast: String { tr("settings.island.speed_fast", "快") }
        static var hapticIntensity: String { tr("settings.island.haptic_intensity", "震感强度") }
        static var hideInFullscreen: String { tr("settings.island.hide_in_fullscreen", "全屏时禁用灵动岛") }

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
                "打开开关后可在灵动岛各自成页展示。拖到另一张卡片可交换库顺序。电量、音量等功能磁贴请到「控制台」。"
            )
        }
        static var libraryTitle: String { tr("widgets.library.title", "小组件库") }
        static var libraryEmpty: String { tr("widgets.library.empty", "暂无可用小组件。") }
        static var notFound: String { tr("widgets.not_found", "找不到该小组件。") }
        static var cannotPreview: String { tr("widgets.cannot_preview", "无法预览") }
        static var pageDotsA11y: String { tr("widgets.page_dots_a11y", "小组件分页") }
        static var meetingPreviewTitle: String { tr("widgets.meeting_preview_title", "下一场会议提醒设置") }
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
            tr("control_deck.module.battery_summary", "本机与键盘、鼠标等电量环形指示")
        }
        static var moduleVolume: String { tr("control_deck.module.volume", "输出音量") }
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
    }

    // MARK: - Helpers

    private static func tr(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue)
    }
}
