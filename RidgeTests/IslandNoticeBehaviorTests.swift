import XCTest
@testable import Ridge

/// 瞬时通知 / RAM 告警行为：免打扰、改规则清 mute、自动收起与收岛策略。
@MainActor
final class IslandNoticeBehaviorTests: XCTestCase {

    override func tearDown() {
        IslandNoticeCenter.shared.dismiss(id: nil)
        ResourceMonitorSettings.shared.clearMute()
        super.tearDown()
    }

    // MARK: - 自动收起策略

    func test_islandNoticeBehavior_autoDismissWaitRules() {
        // 会议等：设置挡住 → 等
        XCTAssertTrue(
            IslandNoticeAutoDismissPolicy.shouldWaitForSettingsUnblock(
                expandsDuringSettingsSession: false,
                settingsBlocksExpand: true
            )
        )
        // 瞬时 tip：设置挡住也立刻计时
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldWaitForSettingsUnblock(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: true
            )
        )
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldWaitForSettingsUnblock(
                expandsDuringSettingsSession: false,
                settingsBlocksExpand: false
            )
        )

        // 悬停保活
        XCTAssertTrue(
            IslandNoticeAutoDismissPolicy.shouldWaitForHoverEnd(
                holdWhileHovering: true,
                isHovering: true
            )
        )
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldWaitForHoverEnd(
                holdWhileHovering: true,
                isHovering: false
            )
        )
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldWaitForHoverEnd(
                holdWhileHovering: false,
                isHovering: true
            )
        )

        XCTAssertEqual(IslandNoticeAutoDismissPolicy.standardNanoseconds, 3_000_000_000)
        XCTAssertEqual(IslandNoticeAutoDismissPolicy.pollNanoseconds, 100_000_000)
    }

    func test_islandNoticeBehavior_everyAutoDismissTipUsesStandardDuration() {
        let tips: [IslandNoticePayload] = [
            .clipboardCaptureHint(id: "copy.b", text: "x", symbol: "doc"),
            .moveReminder(.init(id: "m", activeMinutes: 30, restMinutes: 5)),
            .ramPressure(
                .init(
                    id: "r",
                    ramUsedBytes: 1,
                    ramPercent: 96,
                    topAppName: "A",
                    topAppMemoryBytes: 1
                )
            ),
            .processEnded(
                .init(
                    id: "p",
                    projectName: "x",
                    label: "y",
                    message: "z",
                    endedAt: Date(),
                    outcome: .succeeded,
                    logPath: nil,
                    peakMemoryBytes: 0,
                    durationSeconds: 1
                )
            ),
            .peripheralLowBattery(
                .init(
                    id: "l",
                    deviceID: "d",
                    deviceName: "M",
                    kind: .mouse,
                    percent: 10,
                    threshold: 20,
                    detail: ""
                )
            ),
            .peripheralFullCharge(
                .init(
                    id: "f",
                    deviceID: "d",
                    deviceName: "K",
                    kind: .keyboard,
                    percent: 100,
                    threshold: 100,
                    detail: ""
                )
            ),
            .peripheralConnected(
                .init(
                    id: "c",
                    deviceID: "d",
                    deviceName: "T",
                    kind: .trackpad,
                    percent: 80,
                    threshold: 0,
                    detail: ""
                )
            ),
            .aiUsageAlert(
                id: "ai",
                providerName: "X",
                remainingPercent: 5,
                stage: .critical,
                resetsAt: nil
            )
        ]
        for tip in tips {
            XCTAssertEqual(
                IslandNoticeAutoDismissPolicy.nanoseconds(for: tip),
                IslandNoticeAutoDismissPolicy.standardNanoseconds,
                tip.sourceTag
            )
            XCTAssertTrue(tip.expandsDuringSettingsSession, tip.sourceTag)
        }

        for manual in [
            IslandNoticePayload.meetingLead(meetingID: "m1"),
            .colorPickTip,
            .ocrSelectTip
        ] {
            XCTAssertNil(IslandNoticeAutoDismissPolicy.nanoseconds(for: manual), manual.sourceTag)
            XCTAssertFalse(manual.expandsDuringSettingsSession, manual.sourceTag)
        }
    }

    // MARK: - 通知结束后是否收岛

    func test_islandNoticeBehavior_endCollapsePolicy() {
        XCTAssertTrue(
            IslandNoticeEndCollapsePolicy.isNoticeFullyGone(
                current: nil,
                isTransientNoticePage: false
            )
        )
        XCTAssertFalse(
            IslandNoticeEndCollapsePolicy.isNoticeFullyGone(
                current: .colorPickTip,
                isTransientNoticePage: false
            )
        )
        XCTAssertFalse(
            IslandNoticeEndCollapsePolicy.isNoticeFullyGone(
                current: nil,
                isTransientNoticePage: true
            )
        )

        // 悬停 + 通知已净 + 仍有可悬停面板 → 保展开
        XCTAssertTrue(
            IslandNoticeEndCollapsePolicy.shouldKeepExpandedAfterNoticeEnd(
                hovering: true,
                noticeFullyGone: true,
                allowsHoverExpand: true
            )
        )
        // 悬停但通知页/槽未清 → 必须收（避免空双翼）
        XCTAssertFalse(
            IslandNoticeEndCollapsePolicy.shouldKeepExpandedAfterNoticeEnd(
                hovering: true,
                noticeFullyGone: false,
                allowsHoverExpand: true
            )
        )
        // 不悬停 → 收
        XCTAssertFalse(
            IslandNoticeEndCollapsePolicy.shouldKeepExpandedAfterNoticeEnd(
                hovering: false,
                noticeFullyGone: true,
                allowsHoverExpand: true
            )
        )
        // 无可悬停面板 → 收
        XCTAssertFalse(
            IslandNoticeEndCollapsePolicy.shouldKeepExpandedAfterNoticeEnd(
                hovering: true,
                noticeFullyGone: true,
                allowsHoverExpand: false
            )
        )
    }

    // MARK: - RAM 免打扰立刻撤 tip

    func test_islandNoticeBehavior_muteDismissesRAMTipImmediately() {
        let settings = ResourceMonitorSettings.shared
        settings.clearMute()
        IslandNoticeCenter.shared.dismiss(id: nil)

        let notice = ResourceRAMPressureNotice(
            id: "behavior.ram.mute",
            ramUsedBytes: 28 * 1024 * 1024 * 1024,
            ramPercent: 96,
            topAppName: "Chrome",
            topAppBundleID: "com.google.Chrome",
            topAppMemoryBytes: 4 * 1024 * 1024 * 1024
        )
        IslandNoticeCenter.shared.present(.ramPressure(notice))
        XCTAssertTrue(IslandNoticeCenter.shared.slots.contains(id: notice.id))

        // 队列里再塞一条 RAM，免打扰须一并清
        let queued = ResourceRAMPressureNotice(
            id: "behavior.ram.queued",
            ramUsedBytes: 1,
            ramPercent: 97,
            topAppName: "X",
            topAppMemoryBytes: 1
        )
        IslandNoticeCenter.shared.present(.ramPressure(queued))
        XCTAssertTrue(IslandNoticeCenter.shared.slots.contains(id: notice.id))
        XCTAssertTrue(
            IslandNoticeCenter.shared.slots.contains(id: queued.id),
            "第二条 RAM 应入 FIFO 队列"
        )

        ResourceMonitorSession.shared.muteAlerts30m()

        XCTAssertTrue(settings.isMuted)
        XCTAssertFalse(IslandNoticeCenter.shared.slots.contains(id: notice.id))
        XCTAssertFalse(IslandNoticeCenter.shared.slots.contains(id: queued.id))
        if case .ramPressure = IslandNoticeCenter.shared.current {
            XCTFail("免打扰后不得仍展示 RAM tip")
        }
    }

    // MARK: - 改规则清 mute

    func test_islandNoticeBehavior_rearmClearsMuteWithoutRepublishWhenAlertOff() {
        let settings = ResourceMonitorSettings.shared
        let previousEnabled = settings.alertEnabled
        defer {
            settings.alertEnabled = previousEnabled
            settings.clearMute()
        }

        settings.alertEnabled = false
        settings.muteAlerts(minutes: 30)
        XCTAssertTrue(settings.isMuted)

        IslandNoticeCenter.shared.dismiss(id: nil)
        ResourceMonitorSession.shared.rearmAlertAndEvaluate(reason: "testThreshold")

        XCTAssertFalse(settings.isMuted, "改规则须清免打扰")
        // 告警关着：清 mute 后也不该再投 RAM tip
        if case .ramPressure = IslandNoticeCenter.shared.current {
            XCTFail("告警关闭时 rearm 不得投递 RAM tip")
        }
    }

    func test_islandNoticeBehavior_muteUntilInFutureAndClear() {
        let settings = ResourceMonitorSettings.shared
        settings.clearMute()
        XCTAssertFalse(settings.isMuted)

        settings.muteAlerts(minutes: 30)
        XCTAssertTrue(settings.isMuted)
        XCTAssertNotNil(settings.muteUntil)
        XCTAssertGreaterThan(settings.muteUntil!, Date())

        settings.clearMute()
        XCTAssertFalse(settings.isMuted)
        XCTAssertNil(settings.muteUntil)

        // 过期静音视为未静音
        settings.muteAlerts(minutes: -1)
        settings.clearMuteIfExpired()
        XCTAssertFalse(settings.isMuted)
    }

    // MARK: - 媒体可见 compact（布局驱动）

    func test_islandNoticeBehavior_mediaVisibleCompactFollowsLayout() {
        IslandNoticeCenter.shared.dismiss(id: nil)
        // 无 tip 时：若未在播，isActive 可能 false——只测「有 tip 盖住」分支。
        IslandNoticeCenter.shared.present(.meetingLead(meetingID: "behavior.media.guard"))
        XCTAssertNotNil(IslandNoticeCenter.shared.current)
        XCTAssertFalse(
            MediaCompactPresence.isVisiblyShowingCompact,
            "有会议 tip 时不得认播放小岛可见"
        )
        IslandNoticeCenter.shared.dismiss(id: "meeting.lead.behavior.media.guard")
        XCTAssertNil(IslandNoticeCenter.shared.current)
    }
}
