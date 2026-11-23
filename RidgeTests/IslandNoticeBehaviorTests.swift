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
        XCTAssertEqual(
            IslandNoticeAutoDismissPolicy.copiedNoticeNanoseconds,
            IslandChrome.notchRightOrbAutoDismissNanoseconds
        )
        XCTAssertEqual(
            IslandNoticeAutoDismissPolicy.copiedNoticeNanoseconds,
            IslandChrome.notchRightOrbEntranceNanoseconds
                + IslandChrome.notchRightOrbLingerNanoseconds
        )
        XCTAssertEqual(IslandNoticeAutoDismissPolicy.pollNanoseconds, 100_000_000)
    }

    func test_islandNoticeBehavior_everyAutoDismissTipUsesStandardDuration() {
        let tips: [IslandNoticePayload] = [
            .clipboardCaptureHint(id: "paste.hint", text: "x", symbol: "doc"),
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
            ),
            .macBatteryCharging(
                .init(id: "mac.c", kind: .charging, percent: 60, threshold: 0, detail: "")
            ),
            .macBatteryLow(
                .init(id: "mac.l", kind: .low, percent: 12, threshold: 20, detail: "")
            ),
            .macBatteryFull(
                .init(id: "mac.f", kind: .full, percent: 100, threshold: 100, detail: "")
            ),
            .macBatteryUnplugged(
                .init(id: "mac.u", kind: .unplugged, percent: 64, threshold: 0, detail: "")
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

        let copied = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.b",
            text: "x",
            symbol: "doc"
        )
        XCTAssertEqual(
            IslandNoticeAutoDismissPolicy.nanoseconds(for: copied),
            IslandNoticeAutoDismissPolicy.copiedNoticeNanoseconds
        )
        XCTAssertTrue(copied.expandsDuringSettingsSession)
        XCTAssertFalse(copied.holdsWhileHovering)

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

    // MARK: - 自动收起：可注入时钟（不必真 sleep 3s）

    func test_islandNoticeBehavior_autoDismissShouldDismissNowTimeline() {
        let display = IslandNoticeAutoDismissPolicy.standardNanoseconds

        // 设置挡住 + 会议类（不可在设置中展开）→ 未到点也不收
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: false,
                settingsBlocksExpand: true,
                holdWhileHovering: true,
                isHovering: false,
                elapsedNanoseconds: display,
                displayNanoseconds: display
            )
        )

        // 瞬时 tip：设置挡住也计时；未满时长 → 不收
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: true,
                holdWhileHovering: true,
                isHovering: false,
                elapsedNanoseconds: display / 2,
                displayNanoseconds: display
            )
        )

        // 瞬时 tip：时长够 + 未悬停 → 收
        XCTAssertTrue(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: true,
                holdWhileHovering: true,
                isHovering: false,
                elapsedNanoseconds: display,
                displayNanoseconds: display
            )
        )

        // 时长够但悬停保活 → 不收
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: false,
                holdWhileHovering: true,
                isHovering: true,
                elapsedNanoseconds: display,
                displayNanoseconds: display
            )
        )

        // 时长够 + 悬停但不保活（取色类）→ 收
        XCTAssertTrue(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: false,
                settingsBlocksExpand: false,
                holdWhileHovering: false,
                isHovering: true,
                elapsedNanoseconds: display,
                displayNanoseconds: display
            )
        )

        // 刚到点边界
        XCTAssertTrue(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: false,
                holdWhileHovering: false,
                isHovering: false,
                elapsedNanoseconds: display,
                displayNanoseconds: display
            )
        )
        XCTAssertFalse(
            IslandNoticeAutoDismissPolicy.shouldDismissNow(
                expandsDuringSettingsSession: true,
                settingsBlocksExpand: false,
                holdWhileHovering: false,
                isHovering: false,
                elapsedNanoseconds: display - 1,
                displayNanoseconds: display
            )
        )
    }

    // MARK: - Center 真投递：FIFO + 独占清队

    func test_islandNoticeBehavior_centerFIFOAndExclusiveClearsQueue() {
        let center = IslandNoticeCenter.shared
        center.dismiss(id: nil)

        let first = IslandNoticePayload.aiUsageAlert(
            id: "behavior.ai.1",
            providerName: "A",
            remainingPercent: 5,
            stage: .critical,
            resetsAt: nil
        )
        let second = IslandNoticePayload.peripheralLowBattery(
            .init(
                id: "behavior.bat.2",
                deviceID: "d",
                deviceName: "Mouse",
                kind: .mouse,
                percent: 8,
                threshold: 20,
                detail: "low"
            )
        )
        let third = IslandNoticePayload.processEnded(
            .init(
                id: "behavior.watch.3",
                projectName: "lab",
                label: "sleep",
                message: "ok",
                endedAt: Date(),
                outcome: .succeeded,
                logPath: nil,
                peakMemoryBytes: 0,
                durationSeconds: 1
            )
        )

        center.present(first)
        center.present(second)
        center.present(third)

        XCTAssertEqual(center.slots.secondary?.id, first.id)
        XCTAssertEqual(center.slots.secondaryQueue.map(\.id), [second.id, third.id])
        XCTAssertEqual(center.current?.id, first.id)

        center.dismiss(id: first.id)
        XCTAssertEqual(center.slots.secondary?.id, second.id)
        XCTAssertEqual(center.slots.secondaryQueue.map(\.id), [third.id])

        // 独占清掉队列
        center.present(.colorPickTip)
        XCTAssertEqual(center.slots.primary?.id, IslandNoticePayload.colorPickTipID)
        XCTAssertNil(center.slots.secondary)
        XCTAssertTrue(center.slots.secondaryQueue.isEmpty)
        XCTAssertEqual(center.current?.id, IslandNoticePayload.colorPickTipID)

        // 独占期间 C 不得入槽
        center.present(first)
        XCTAssertNil(center.slots.secondary)
        XCTAssertTrue(center.slots.secondaryQueue.isEmpty)

        center.dismiss(id: IslandNoticePayload.colorPickTipID)
        XCTAssertNil(center.current)
    }

    // MARK: - 进程结束 tip：按岛 tip id 撤，不被控制台旧 lastWatchEnded 绑死

    func test_islandNoticeBehavior_processEndedDismissByTipIDNotStaleLocal() {
        XCTAssertFalse(
            ProjectWatchEndedDismissSync.shouldClearLocalEnded(localID: "ended:old", islandTipID: "projects.watch.debug.lab")
        )
        XCTAssertTrue(
            ProjectWatchEndedDismissSync.shouldClearLocalEnded(
                localID: "projects.watch.debug.lab",
                islandTipID: "projects.watch.debug.lab"
            )
        )
        XCTAssertFalse(
            ProjectWatchEndedDismissSync.shouldClearLocalEnded(localID: nil, islandTipID: "projects.watch.debug.lab")
        )

        let center = IslandNoticeCenter.shared
        center.dismiss(id: nil)
        defer { center.dismiss(id: nil) }

        let lab = IslandNoticePayload.processEnded(
            .init(
                id: "projects.watch.debug.lab",
                projectName: "Ridge Lab",
                label: "lab-ok",
                message: "ok",
                endedAt: Date(),
                outcome: .succeeded,
                logPath: nil,
                peakMemoryBytes: 0,
                durationSeconds: 1
            )
        )
        center.present(lab)
        XCTAssertEqual(center.slots.secondary?.id, lab.id)
        XCTAssertEqual(lab.autoDismissNanoseconds, IslandNoticeAutoDismissPolicy.standardNanoseconds)

        // 模拟旧路径按「控制台旧 id」撤：岛上测试 tip 必须还在。
        center.dismiss(id: "ended:999:stale")
        XCTAssertEqual(center.slots.secondary?.id, lab.id, "旧 lastWatchEnded id 不得误撤测试台 tip")

        center.dismiss(id: lab.id)
        XCTAssertNil(center.slots.secondary)
        XCTAssertNil(center.current)
    }

    // MARK: - 改阈值清 mute（告警开着也只清 mute，不强行要求立刻再投）

    func test_islandNoticeBehavior_rearmClearsMuteWhenAlertEnabled() {
        let settings = ResourceMonitorSettings.shared
        let previousEnabled = settings.alertEnabled
        let previousThreshold = settings.ramThresholdPercent
        defer {
            settings.alertEnabled = previousEnabled
            settings.ramThresholdPercent = previousThreshold
            settings.clearMute()
            IslandNoticeCenter.shared.dismiss(id: nil)
        }

        settings.alertEnabled = true
        settings.muteAlerts(minutes: 30)
        XCTAssertTrue(settings.isMuted)

        ResourceMonitorSession.shared.rearmAlertAndEvaluate(reason: "testThresholdChange")
        XCTAssertFalse(settings.isMuted, "改阈值须清免打扰，否则新规则被旧 mute 挡住")
    }

    // MARK: - 专注待命：仅计时/加时

    func test_islandNoticeBehavior_focusCompactStandbyOnlyWhileTiming() {
        let focus = FocusTimerSession.shared
        let previousEnabled = focus.isWidgetEnabled
        defer {
            focus.setWidgetEnabled(false)
            if previousEnabled {
                focus.setWidgetEnabled(true)
            }
            IslandNoticeCenter.shared.dismiss(id: nil)
        }

        focus.setWidgetEnabled(false)
        XCTAssertFalse(focus.showsCompactStandby)

        focus.setWidgetEnabled(true)
        // 选时态：不上待命翼
        XCTAssertEqual(focus.phase, .picking)
        XCTAssertFalse(focus.showsCompactStandby)

        #if DEBUG
        focus.debugEnterRunning(minutes: 10)
        XCTAssertEqual(focus.phase, .running)
        XCTAssertTrue(focus.showsCompactStandby)

        focus.debugJumpIntoOvertime()
        XCTAssertEqual(focus.phase, .overtime)
        XCTAssertTrue(focus.showsCompactStandby)

        focus.debugEnterCountUp(elapsedSeconds: 90)
        XCTAssertEqual(focus.phase, .countUp)
        XCTAssertTrue(focus.showsCompactStandby)
        XCTAssertFalse(focus.snapshot.isPaused)

        focus.toggleCountUpPause()
        XCTAssertTrue(focus.snapshot.isPaused)
        focus.toggleCountUpPause()
        XCTAssertFalse(focus.snapshot.isPaused)

        focus.finishEarly()
        XCTAssertEqual(focus.phase, .completed)
        XCTAssertFalse(focus.showsCompactStandby)
        focus.dismissCompletion()
        #endif

        focus.setWidgetEnabled(false)
        XCTAssertFalse(focus.showsCompactStandby)
    }
}
