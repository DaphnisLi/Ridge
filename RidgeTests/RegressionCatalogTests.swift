import SwiftUI
import XCTest
@testable import Ridge

/// 对齐 `docs/REGRESSION_CATALOG.md` 中 `recurring: true` 项的自动化锚点。
/// 用例名含 catalog `id`，改 Island / 控制台 / 预览后必须先跑本 target。
final class RegressionCatalogTests: XCTestCase {

    // MARK: - island-hover-retention

    func test_islandHoverRetention_lowerHalfOfLargePanelStaysInRetention() {
        let notch = CGRect(x: 400, y: 900, width: 180, height: 32)
        let panel = CGRect(x: 200, y: 700, width: 660, height: 300)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: true
        )
        let midLower = CGPoint(x: panel.midX, y: panel.minY + 40)
        XCTAssertTrue(frame.contains(midLower), "大岛下半截必须仍在保展开区")
    }

    func test_islandHoverRetention_collapsedMediaCompactWingsAreInRetention() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let compact = CGRect(x: 311, y: 962, width: 380, height: 38)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: compact,
            expanded: false
        )
        let leftWing = CGPoint(x: compact.minX + 12, y: compact.midY)
        XCTAssertTrue(frame.contains(leftWing), "收起态播放小岛两翼须可悬停展开，不能只用刘海")
    }

    func test_islandHoverRetention_rejectsAccidentalShrinkToNotch() {
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: CGSize(width: 660, height: 300),
                measured: CGSize(width: 180, height: 32),
                isExpanded: true,
                allowShrink: false
            )
        )
    }

    func test_islandHoverRetention_shortTipDoesNotPoisonStablePreference() {
        let notch = CGSize(width: 179, height: 32)
        let tip = CGSize(width: 275, height: 68)
        let stable = CGSize(width: 660, height: 300)
        XCTAssertTrue(IslandExpandedPanelPolicy.isTransientShortPanel(tip, notch: notch))
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: tip,
                stable: stable,
                notch: notch,
                isExpanded: true
            )
        )
    }

    // MARK: - shelf-copied-notice-miss

    /// 关货架、开 tip 仍须监听剪贴板；否则独立 tip 形同虚设（shelf-copied-notice-miss）。
    func test_shelfCopiedNoticeMiss_monitorPasteboardWhenTipOnEvenIfShelfOff() {
        XCTAssertTrue(
            ClipboardCopiedNoticeGate.shouldMonitorPasteboard(shelfEnabled: false, tipEnabled: true),
            "已复制 tip 开启时，关货架也必须轮询剪贴板"
        )
        XCTAssertTrue(
            ClipboardCopiedNoticeGate.shouldMonitorPasteboard(shelfEnabled: true, tipEnabled: false),
            "货架开启时应监听（历史进货架）"
        )
        XCTAssertFalse(
            ClipboardCopiedNoticeGate.shouldMonitorPasteboard(shelfEnabled: false, tipEnabled: false),
            "货架与 tip 都关才停监听"
        )
        XCTAssertEqual(ClipboardCopiedNoticeGate.widgetID, "builtin.copiedNotice")
    }

    @MainActor
    func test_shelfCopiedNoticeMiss_gateDefaultsToWidgetLibrarySwitch() {
        // 闸门必须读 tip 库开关，禁止再绑死已删除的货架嵌套开关。
        XCTAssertEqual(
            ShelfSettings.shared.showCopiedNotice,
            ClipboardCopiedNoticeGate.isTipEnabled
        )
    }

    /// 取色 / 框选翼引导 →「已复制」短条：缩宽必须可应用，否则卡在翼高看不见提示。
    func test_shelfCopiedNoticeMiss_wingGuideToCopiedAllowsWidthShrink() {
        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: notchW, notchHeight: notchH)
        let short = IslandChrome.preparedShortTipPanelSize(notchWidth: notchW, notchHeight: notchH)

        XCTAssertTrue(IslandNoticePayload.colorPickTip.usesNotchWingChrome)
        XCTAssertTrue(IslandNoticePayload.ocrSelectTip.usesNotchWingChrome)
        let copied = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.color.test",
            text: "已复制",
            symbol: "eyedropper"
        )
        XCTAssertTrue(copied.usesShortBelowNotchChrome)
        XCTAssertFalse(copied.usesNotchWingChrome)
        // Cmd+C 后指针常不在岛上：须保持展开至自动收起，否则展开中途就被 hoverEnd 收掉。
        XCTAssertTrue(copied.keepsExpandedWithoutHover)
        XCTAssertEqual(copied.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertTrue(copied.holdsWhileHovering)

        // 短条须明显高于翼条，才能容纳 shortTip 顶距；否则文案被顶出。
        XCTAssertGreaterThan(
            short.height,
            IslandChrome.shortTipTopInset(notchHeight: notchH),
            "短条高度须大于顶距，文案才有可视区"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: wing,
                measured: short,
                isExpanded: true,
                allowShrink: false
            ),
            "翼→已复制：无 allowShrink 窗口也须放行（shelf-copied-notice-miss）"
        )
    }

    func test_shelfCopiedNoticeMiss_preparedShortTipTallerThanWingChrome() {
        // 预备尺寸契约：present(copy) 先 force 到 short，再换皮。
        let short = IslandChrome.preparedShortTipPanelSize(notchWidth: 160, notchHeight: 32)
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: 160, notchHeight: 32)
        XCTAssertGreaterThanOrEqual(short.height, wing.height)
        XCTAssertLessThan(short.width, wing.width)
        XCTAssertEqual(IslandChrome.shortTipContentHeight, 30)
        XCTAssertEqual(IslandChrome.preparedWingWidth, 98)
    }

    func test_islandHoverRetention_contentScrollHoldsExpandWithinGrace() {
        let now = Date()
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: now.addingTimeInterval(-0.2),
                now: now
            ),
            "纵滑后宽限内必须保展开（滚一半误收回归）"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: now.addingTimeInterval(-2.0),
                now: now
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldHoldExpandForRecentScroll(
                lastScrollAt: nil,
                now: now
            )
        )
    }

    // MARK: - island-chrome-double-padding

    func test_islandChromeDoublePadding_contentBottomMatchesHorizontal() {
        // 壳层左右与底同值；内容根再加 padding 即叠两层（规则：根视图禁止外圈 padding）。
        XCTAssertEqual(IslandChrome.contentBottom, IslandChrome.contentHorizontal)
        XCTAssertEqual(IslandChrome.horizontalInsetTotal, IslandChrome.contentHorizontal * 2)
        XCTAssertGreaterThan(IslandChrome.contentBottom, 0)
    }

    func test_islandChromeDoublePadding_tokensAreFixed() {
        // 左右 / 底是固定令牌；改数须有意为之，并同步本用例。
        XCTAssertEqual(IslandChrome.contentHorizontal, 14)
        XCTAssertEqual(IslandChrome.contentBottom, 14)
        XCTAssertEqual(IslandChrome.compactTipTopInset, 0)
        XCTAssertEqual(IslandChrome.compactTipBottom, 4)
        XCTAssertEqual(IslandChrome.shortTipBottom, 6)
        XCTAssertLessThan(IslandChrome.compactTipBottom, IslandChrome.contentBottom)
        XCTAssertLessThan(IslandChrome.shortTipBottom, IslandChrome.contentBottom)
    }

    func test_islandChromeDoublePadding_surfaceInsetsLockHorizontalAndBottom() {
        let notchH: CGFloat = 32
        let expanded = IslandChrome.insets(for: .expanded, notchHeight: notchH)
        let wing = IslandChrome.insets(for: .notchWingTip, notchHeight: notchH)
        let shortTip = IslandChrome.insets(for: .shortBelowNotchTip, notchHeight: notchH)
        let notice = IslandChrome.insets(for: .notice, notchHeight: notchH)

        // 所有表面左右边距同一固定令牌。
        for insets in [expanded, wing, shortTip, notice] {
            XCTAssertEqual(insets.horizontal, IslandChrome.contentHorizontal)
        }

        XCTAssertEqual(expanded.bottom, IslandChrome.contentBottom)
        XCTAssertEqual(notice.bottom, IslandChrome.contentBottom)
        // 翼 tip / 短 tip 底距必须用紧凑令牌，禁止误退回 contentBottom（会议 tip 曾叠大底距）。
        XCTAssertEqual(wing.bottom, IslandChrome.compactTipBottom)
        XCTAssertEqual(wing.top, IslandChrome.compactTipTopInset)
        XCTAssertEqual(shortTip.bottom, IslandChrome.shortTipBottom)
        XCTAssertNotEqual(wing.bottom, IslandChrome.contentBottom)
        XCTAssertNotEqual(shortTip.bottom, IslandChrome.contentBottom)
    }

    func test_islandChrome_meetingUsesNotchWing_othersShortCapsule() {
        // 会议 / AI / 久坐 / 取色 / 框选：左右翼贴刘海；「已复制」仍为矮胶囊短条。
        let meeting = IslandNoticePayload.meetingLead(meetingID: "test-meeting")
        let aiUsage = IslandNoticePayload.aiUsageAlert(
            id: "aiUsage.test",
            providerName: "Cursor",
            remainingPercent: 40,
            stage: .warning,
            resetsAt: Date().addingTimeInterval(9 * 3600)
        )
        let move = IslandNoticePayload.moveReminder(
            .init(id: "move.test", activeMinutes: 30, restMinutes: 2)
        )
        let copied = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.test",
            text: "已复制",
            symbol: "doc.on.doc"
        )
        XCTAssertTrue(meeting.usesNotchWingChrome)
        XCTAssertFalse(meeting.usesShortBelowNotchChrome)
        XCTAssertTrue(aiUsage.usesNotchWingChrome)
        XCTAssertFalse(aiUsage.usesShortBelowNotchChrome)
        XCTAssertTrue(move.usesNotchWingChrome)
        XCTAssertFalse(move.usesShortBelowNotchChrome)
        XCTAssertTrue(IslandNoticePayload.colorPickTip.usesNotchWingChrome)
        XCTAssertFalse(IslandNoticePayload.colorPickTip.usesShortBelowNotchChrome)
        XCTAssertTrue(IslandNoticePayload.ocrSelectTip.usesNotchWingChrome)
        XCTAssertFalse(IslandNoticePayload.ocrSelectTip.usesShortBelowNotchChrome)
        XCTAssertFalse(copied.usesNotchWingChrome)
        XCTAssertTrue(copied.usesShortBelowNotchChrome)
    }

    /// AI 额度右翼重置文案三档。
    func test_aiUsageResetCountdown_tiersMatchSpec() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            AIUsageIslandCardView.resetCountdownText(now.addingTimeInterval(14 * 86_400), now: now),
            "重置 14d 后"
        )
        XCTAssertEqual(
            AIUsageIslandCardView.resetCountdownText(now.addingTimeInterval(9 * 3600), now: now),
            "重置 9h 后"
        )
        XCTAssertEqual(
            AIUsageIslandCardView.resetCountdownText(now.addingTimeInterval(47 * 60), now: now),
            "47m 重置"
        )
        // 边界：恰 24h → 小时档；恰 1h → 分钟档。
        XCTAssertEqual(
            AIUsageIslandCardView.resetCountdownText(now.addingTimeInterval(24 * 3600), now: now),
            "重置 24h 后"
        )
        XCTAssertEqual(
            AIUsageIslandCardView.resetCountdownText(now.addingTimeInterval(3600), now: now),
            "60m 重置"
        )
    }

    func test_meetingLead_keepsExpandedWithoutHover() {
        // 会前提示常驻到入会/结束；移开指针不得 hoverEnd 收岛。
        let meeting = IslandNoticePayload.meetingLead(meetingID: "test-meeting")
        XCTAssertTrue(meeting.keepsExpandedWithoutHover)
        XCTAssertNil(meeting.autoDismissNanoseconds)
    }

    /// meeting-tip-preemption：会议 tip 在场时，其它瞬时通知不得盖住。
    func test_meetingTipPreemption_blocksLowerPriorityWhileMeetingShowing() {
        let meeting = IslandNoticePayload.meetingLead(meetingID: "m1")
        let otherMeeting = IslandNoticePayload.meetingLead(meetingID: "m2")
        let copy = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.test",
            text: "已复制",
            symbol: "doc.on.doc"
        )
        let ram = IslandNoticePayload.colorPickTip

        XCTAssertEqual(meeting.preemptionRank, 100)
        XCTAssertEqual(copy.preemptionRank, 0)
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: nil))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: copy))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: otherMeeting, replacing: meeting))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: meeting))
        XCTAssertFalse(IslandNoticePreemption.shouldAccept(incoming: copy, replacing: meeting))
        XCTAssertFalse(IslandNoticePreemption.shouldAccept(incoming: ram, replacing: meeting))
    }

    func test_islandOutline_panelKeepsSquareTopCorners() {
        // tip-outline：真岛 / 预览一律上直角；左上 (1,1) 须在路径内。
        let rect = CGRect(x: 0, y: 0, width: 200, height: 40)
        let panel = IslandPanelShape(bottomRadius: 12).path(in: rect)
        XCTAssertTrue(panel.contains(CGPoint(x: 1, y: 1)), "左上应为直角填实")
        XCTAssertTrue(panel.contains(CGPoint(x: 199, y: 1)), "右上应为直角填实")
        XCTAssertFalse(panel.contains(CGPoint(x: 1, y: 39)), "左下应挖空圆角")
        XCTAssertTrue(panel.contains(CGPoint(x: 100, y: 20)))
    }

    @MainActor
    func test_meetingTipDismiss_retainWindowMatchesMode() {
        let settings = MeetingSettings.shared
        let previousMode = settings.tipDismissMode
        let previousMinutes = settings.tipDismissMinutes
        defer {
            settings.tipDismissMode = previousMode
            settings.tipDismissMinutes = previousMinutes
        }

        settings.tipDismissMode = .atStart
        XCTAssertTrue(settings.shouldRetainLeadTip(secondsToStart: 60, secondsToEnd: 3600))
        XCTAssertFalse(settings.shouldRetainLeadTip(secondsToStart: 0, secondsToEnd: 3600))
        XCTAssertFalse(settings.shouldRetainLeadTip(secondsToStart: -1, secondsToEnd: 3600))

        settings.tipDismissMode = .afterMinutes
        settings.tipDismissMinutes = 5
        XCTAssertTrue(settings.shouldRetainLeadTip(secondsToStart: -299, secondsToEnd: 3600))
        XCTAssertFalse(settings.shouldRetainLeadTip(secondsToStart: -300, secondsToEnd: 3600))

        settings.tipDismissMode = .untilEnd
        XCTAssertTrue(settings.shouldRetainLeadTip(secondsToStart: -600, secondsToEnd: 10))
        XCTAssertFalse(settings.shouldRetainLeadTip(secondsToStart: -600, secondsToEnd: 0))
    }

    /// meeting-tip-advance-next：第一场开始后保留窗口结束，应立刻选中仍在 lead 窗口内的第二场。
    func test_meetingTipAdvanceNext_selectsSecondWhenFirstGraceExpired() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = MeetingEvent(
            id: "m1",
            title: "第一场",
            startDate: now.addingTimeInterval(-6 * 60),
            endDate: now.addingTimeInterval(24 * 60),
            calendarIdentifier: "cal",
            calendarTitle: "日历",
            join: nil
        )
        let second = MeetingEvent(
            id: "m2",
            title: "第二场",
            startDate: now.addingTimeInterval(4 * 60),
            endDate: now.addingTimeInterval(34 * 60),
            calendarIdentifier: "cal",
            calendarTitle: "日历",
            join: nil
        )

        let afterFirstGrace = MeetingLeadTipSelector.Input(
            now: now,
            leadSeconds: 10 * 60,
            tipDismissMode: .afterMinutes,
            tipDismissMinutes: 5,
            dismissedAfterJoinID: nil,
            latchedMeetingID: first.id
        )
        let selected = MeetingLeadTipSelector.select(from: [first, second], input: afterFirstGrace)
        XCTAssertEqual(selected?.meeting.id, second.id)

        // 第一场开始后仅 3 分钟：仍在 5 分钟保留内，应继续 latched 第一场。
        let duringFirstGrace = MeetingLeadTipSelector.Input(
            now: first.startDate.addingTimeInterval(3 * 60),
            leadSeconds: 10 * 60,
            tipDismissMode: .afterMinutes,
            tipDismissMinutes: 5,
            dismissedAfterJoinID: nil,
            latchedMeetingID: first.id
        )
        XCTAssertEqual(
            MeetingLeadTipSelector.select(from: [first, second], input: duringFirstGrace)?.meeting.id,
            first.id
        )
    }

    /// 入会撤掉第一场后，第二场已进入 lead 窗口时应被选中。
    func test_meetingTipAdvanceNext_selectsSecondAfterJoinDismiss() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = MeetingEvent(
            id: "m1",
            title: "第一场",
            startDate: now.addingTimeInterval(-2 * 60),
            endDate: now.addingTimeInterval(28 * 60),
            calendarIdentifier: "cal",
            calendarTitle: "日历",
            join: nil
        )
        let second = MeetingEvent(
            id: "m2",
            title: "第二场",
            startDate: now.addingTimeInterval(5 * 60),
            endDate: now.addingTimeInterval(35 * 60),
            calendarIdentifier: "cal",
            calendarTitle: "日历",
            join: nil
        )
        let input = MeetingLeadTipSelector.Input(
            now: now,
            leadSeconds: 10 * 60,
            tipDismissMode: .afterMinutes,
            tipDismissMinutes: 5,
            dismissedAfterJoinID: first.id,
            latchedMeetingID: nil
        )
        let selected = MeetingLeadTipSelector.select(from: [first, second], input: input)
        XCTAssertEqual(selected?.meeting.id, second.id)
    }

    func test_islandFocusPolicy_neverStealsOnHoverOrPlainClick() {
        // island-focus-steal：悬停关穿透 / 展开 / 普通点击均不得 activate；穿透开启须交还 key。
        // 普通点击仍须 makeKey，否则 SwiftUI 按钮首击无响应。
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppWhenDisablingClickThrough)
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppOnExpand)
        XCTAssertFalse(IslandFocusPolicy.shouldActivateAppOnPlainIslandMouseDown)
        XCTAssertTrue(IslandFocusPolicy.shouldMakeKeyOnPlainIslandMouseDown)
        XCTAssertTrue(IslandFocusPolicy.shouldResignKeyWhenEnablingClickThrough)
    }


    // MARK: - settings-preview-live-data（股票样张条数）

    func test_settingsPreviewLiveData_stockSampleUsesFixedFakePair() {
        // 库卡/详情必须假数据固定两卡，禁止实时行情空态。
        let sample = StockIslandView.previewSnapshots()
        XCTAssertEqual(sample.count, 2, "股票设置预览样张必须固定 2 条")
    }

    // MARK: - library-island-stage-stretch（电量预览勿按双行留黑空）

    @MainActor
    func test_libraryIslandStageStretch_batteryPreviewSingleRowHeight() {
        let devices = BatteryDeckView.sampleDevices
        XCTAssertEqual(devices.count, 2, "电量样张固定 2 台一行")
        XCTAssertLessThanOrEqual(
            devices.count,
            NotchGeometry.batteryDeckColumns,
            "样张不得超过单行列数，否则应改双行高"
        )
        let detailH = WidgetSamplePreview.batterySampleContentHeight(compact: false)
        let compactH = WidgetSamplePreview.batterySampleContentHeight(compact: true)
        XCTAssertEqual(
            detailH,
            ControlDeckContentSize.batteryContentCanvasHeight(deviceCount: 2),
            "详情预览画布须与真岛内容高一致"
        )
        XCTAssertEqual(compactH, detailH)
        XCTAssertTrue(
            WidgetSamplePreview.hugsIslandContent(for: "system.controlDeck.battery"),
            "电量预览黑岛须 hugs"
        )
        XCTAssertTrue(
            WidgetSamplePreview.contentProvidesOpaqueShell(for: "system.controlDeck.battery"),
            "电量预览自带岛底（sRGB palette.fill），避免 device 黑在设置窗发灰"
        )
        // 经典黑预览底须为纯黑，与「正在播放」等库卡一致。
        XCTAssertEqual(
            IslandTheme.midnight.palette.fill,
            Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
        )
        XCTAssertEqual(
            ControlDeckContentSize.batteryPanelHeight(deviceCount: 2, notchHeight: 32),
            IslandChrome.expandedTopInset(notchHeight: 32)
                + detailH
                + IslandChrome.contentBottom
        )
        XCTAssertLessThan(detailH, 140)
    }

    // MARK: - settings-preview-island-appearance（预览深色 + 可见顶距；禁 disabled 降透明度）

    @MainActor
    func test_settingsPreviewIslandAppearance_visibleTopInsetAndAbsoluteFill() {
        // 设置预览无刘海遮挡：顶距只留可见间隙，勿照搬含盲区的 expandedTopInset。
        let notch: CGFloat = 32
        let visible = IslandChrome.previewExpandedVisibleTopInset(notchHeight: notch)
        let full = IslandChrome.expandedTopInset(notchHeight: notch)
        XCTAssertEqual(visible, max(IslandChrome.contentBottom, full - notch))
        XCTAssertLessThan(visible, full, "预览顶距须短于真岛含盲区顶距，避免大块空黑发闷")
        // 经典黑底保持 sRGB 纯黑（与真岛视觉对齐的设置窗路径）。
        XCTAssertEqual(
            IslandTheme.midnight.palette.fill,
            Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
        )
        // 预览样张须走假数据路径；卡片交互用 allowsHitTesting，禁止 Button.disabled（会整卡降透明度）。
        XCTAssertEqual(BatteryDeckView.sampleDevices.count, 2)
        XCTAssertTrue(
            WidgetSamplePreview.contentProvidesOpaqueShell(for: "system.controlDeck.battery")
        )
    }

    // MARK: - volume adaptive height（控制台混音台）

    func test_controlDeckVolumeHeight_adaptsBelowMaxAndCapsAtMax() {
        let maxPanel = NotchGeometry.controlDeckMinHeight
        let sparse = ControlDeckContentSize.volumePanelHeight(deviceCount: 1, appCount: 0)
        let dense = ControlDeckContentSize.volumePanelHeight(deviceCount: 5, appCount: 7)
        XCTAssertLessThan(sparse, maxPanel, "内容少时应矮于原最大高度")
        XCTAssertEqual(dense, maxPanel, "内容多时不得超过原最大高度")
        XCTAssertGreaterThanOrEqual(sparse, 148)
    }

    /// 电量岛：列数/行数随台数收缩；两台不得占满三列宽。
    func test_controlDeckBattery_adaptsWidthAndCapsAtTwoRows() {
        XCTAssertEqual(ControlDeckContentSize.batteryColumnCount(deviceCount: 1), 1)
        XCTAssertEqual(ControlDeckContentSize.batteryColumnCount(deviceCount: 2), 2)
        XCTAssertEqual(ControlDeckContentSize.batteryColumnCount(deviceCount: 3), 3)
        XCTAssertEqual(ControlDeckContentSize.batteryColumnCount(deviceCount: 5), 3)

        XCTAssertEqual(ControlDeckContentSize.batteryVisualRowCount(deviceCount: 2), 1)
        XCTAssertEqual(ControlDeckContentSize.batteryVisualRowCount(deviceCount: 3), 1)
        XCTAssertEqual(ControlDeckContentSize.batteryVisualRowCount(deviceCount: 4), 2)
        XCTAssertEqual(ControlDeckContentSize.batteryVisualRowCount(deviceCount: 9), 2)

        let full = ControlDeckContentSize.width
        let two = ControlDeckContentSize.batteryContentWidth(deviceCount: 2)
        let three = ControlDeckContentSize.batteryContentWidth(deviceCount: 3)
        XCTAssertLessThan(two, three, "两台应明显窄于三台满宽")
        XCTAssertEqual(three, full)

        let oneRowCanvas = ControlDeckContentSize.batteryContentCanvasHeight(deviceCount: 2)
        let twoRowCanvas = ControlDeckContentSize.batteryContentCanvasHeight(deviceCount: 5)
        XCTAssertEqual(
            oneRowCanvas,
            ControlDeckContentSize.batteryGridPadTop
                + ControlDeckContentSize.batteryGridPadBottom
                + ControlDeckContentSize.batteryCardHeight
        )
        XCTAssertEqual(
            twoRowCanvas,
            ControlDeckContentSize.batteryGridPadTop
                + ControlDeckContentSize.batteryGridPadBottom
                + ControlDeckContentSize.batteryCardHeight * 2
                + ControlDeckContentSize.batteryRowSpacing
        )
        XCTAssertLessThan(oneRowCanvas, twoRowCanvas)
        // 画布贴合卡片，不得再按旧 178 面板减 chrome 多留底空。
        XCTAssertLessThan(oneRowCanvas, 140)
    }

    // MARK: - widget library family（提示 → 实况 → 面板）

    func test_widgetLibraryFamily_displayOrderIsTipLivePanel() {
        XCTAssertEqual(
            WidgetLibraryFamily.displayOrder,
            [.tip, .live, .panel]
        )
    }

    func test_widgetLibraryFamily_mapsKnownWidgets() {
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.meeting"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.peripheralTip"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.copiedNotice"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.media"), .live)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "system.controlDeck.battery"), .live)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "system.controlDeck.volume"), .panel)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.focusTimer"), .panel)
        XCTAssertNil(WidgetLibraryFamily.family(for: "system.empty"))
    }

    @MainActor
    func test_widgetLibraryFamily_peripheralAndCopiedTipsNeverContentPage() {
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.peripheralTip"))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.copiedNotice"))
    }

    func test_islandNoticePayload_peripheralConnectedIsTransient() {
        let notice = BatteryPeripheralNotice(
            id: "test.connect",
            deviceID: "d1",
            deviceName: "Mouse",
            kind: .mouse,
            percent: 80,
            threshold: 0,
            detail: "connected"
        )
        let payload = IslandNoticePayload.peripheralConnected(notice)
        XCTAssertEqual(payload.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertEqual(payload.sourceTag, "battery.connect")
        XCTAssertTrue(payload.usesNotchWingChrome)
        XCTAssertEqual(
            PeripheralBatteryNoticeCard.cleanedDeviceName("妙控鼠标 2 0x3C44"),
            "妙控鼠标 2"
        )
    }

    func test_widgetLibraryFamily_tipNeverPlacesContentDirectly() {
        XCTAssertFalse(WidgetLibraryFamily.tip.placesContentDirectlyOnIsland)
        XCTAssertFalse(WidgetLibraryFamily.live.placesContentDirectlyOnIsland)
        XCTAssertTrue(WidgetLibraryFamily.panel.placesContentDirectlyOnIsland)
    }

    @MainActor
    func test_widgetLibraryFamily_tipAndClosedLiveRejectedFromContentPage() {
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testReset")
        LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "testReset")
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.meeting"))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.batteryID))
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage("builtin.focusTimer"))
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage("system.controlDeck.volume"))
    }

    /// live-invite-removed：实况有状态时 admit 即可上岛，不再依赖「打开」邀请 tip。
    @MainActor
    func test_liveInviteRemoved_admitAllowsContentPage() {
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testReset")
        LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "testReset")
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))
        LiveIslandGate.shared.admit(LiveIslandGate.mediaID, reason: "test")
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))
        LiveIslandGate.shared.admit(LiveIslandGate.batteryID, reason: "test")
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.batteryID))
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testReset")
        LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "testReset")
    }

    /// 收起态小岛：高度统一，正在播放宽度不得窄于番茄翼。
    func test_compactIsland_sharedHeightAndMediaWidth() {
        XCTAssertEqual(NotchGeometry.focusTimerCompactHeight, NotchGeometry.compactIslandHeight)
        XCTAssertEqual(NotchGeometry.mediaCompactHeight, NotchGeometry.compactIslandHeight)
        XCTAssertGreaterThanOrEqual(
            NotchGeometry.mediaCompactWidth,
            NotchGeometry.focusTimerCompactWidth,
            "播放小岛曾用 300 明显偏窄，至少与番茄翼同宽或更宽"
        )
    }

    /// media-compact-not-resident：媒体大面板默认关闭；悬停准入后 close 须再拒绝（勿用 open，避免测里拉起 MediaRemote）。
    @MainActor
    func test_mediaCompactNotResident_gateClosedUntilOpen() {
        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testReset")
        XCTAssertFalse(LiveIslandGate.shared.isOpened(LiveIslandGate.mediaID))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))

        // 产品上是 compactHover → open；闸门语义与 admit 相同，测 admit 避免 ensureInstance 拖死。
        LiveIslandGate.shared.admit(LiveIslandGate.mediaID, reason: "testCompactHover")
        XCTAssertTrue(LiveIslandGate.shared.isOpened(LiveIslandGate.mediaID))
        XCTAssertTrue(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))

        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "testCollapse")
        XCTAssertFalse(LiveIslandGate.shared.isOpened(LiveIslandGate.mediaID))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage(LiveIslandGate.mediaID))
        XCTAssertFalse(WidgetRuntime.shared.isDemanding(LiveIslandGate.mediaID))
    }

    /// media-compact-not-resident：有会议 tip 盖住时不算「正显示播放小岛」，不得开媒体大面板。
    @MainActor
    func test_mediaCompactNotResident_meetingTipBlocksVisibleCompact() {
        IslandNoticeCenter.shared.dismiss(id: nil)
        // 无 tip 时：仅看 isActive 不够，isVisiblyShowingCompact 还要求 current == nil。
        XCTAssertNil(IslandNoticeCenter.shared.current)
        IslandNoticeCenter.shared.present(.meetingLead(meetingID: "media-hover-guard"))
        XCTAssertNotNil(IslandNoticeCenter.shared.current)
        XCTAssertFalse(
            MediaCompactPresence.isVisiblyShowingCompact,
            "会议 tip 在场时悬停不得开播放大面板"
        )
        IslandNoticeCenter.shared.dismiss(id: "meeting.lead.media-hover-guard")
        XCTAssertNil(IslandNoticeCenter.shared.current)
    }
}
