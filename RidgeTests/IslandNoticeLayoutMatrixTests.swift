import XCTest
@testable import Ridge

/// 岛展示规则穷举：布局真值表 + 全部 tip 契约 + 投递/撤回矩阵。
/// 新增 `IslandNoticePayload` case 或改 `resolvedLayout` 时本文件必须同步，禁止漏测。
final class IslandNoticeLayoutMatrixTests: XCTestCase {

    // MARK: - Fixtures

    private let meeting = IslandNoticePayload.meetingLead(meetingID: "matrix.meeting")
    private let copy = IslandNoticePayload.clipboardCaptureHint(
        id: "copy.matrix",
        text: "已复制",
        symbol: "doc.on.doc"
    )
    private let exclusive = IslandNoticePayload.colorPickTip
    private let ocr = IslandNoticePayload.ocrSelectTip

    private var ram: IslandNoticePayload {
        .ramPressure(
            .init(
                id: "matrix.ram",
                ramUsedBytes: 30 * 1024 * 1024 * 1024,
                ramPercent: 96,
                topAppName: "Chrome",
                topAppBundleID: "com.google.Chrome",
                topAppMemoryBytes: 4 * 1024 * 1024 * 1024
            )
        )
    }

    private var processEnded: IslandNoticePayload {
        .processEnded(
            .init(
                id: "matrix.watch",
                projectName: "ridge",
                label: "dev",
                message: "ridge / dev",
                endedAt: Date(),
                outcome: .succeeded,
                logPath: nil,
                peakMemoryBytes: 100,
                durationSeconds: 12
            )
        )
    }

    private var move: IslandNoticePayload {
        .moveReminder(.init(id: "matrix.move", activeMinutes: 30, restMinutes: 5))
    }

    private var ai: IslandNoticePayload {
        .aiUsageAlert(
            id: "matrix.ai",
            providerName: "Claude",
            remainingPercent: 8,
            stage: .critical,
            resetsAt: nil
        )
    }

    private var peripheralLow: IslandNoticePayload {
        .peripheralLowBattery(
            .init(
                id: "matrix.bat.low",
                deviceID: "d1",
                deviceName: "Mouse",
                kind: .mouse,
                percent: 12,
                threshold: 20,
                detail: "low"
            )
        )
    }

    private var peripheralFull: IslandNoticePayload {
        .peripheralFullCharge(
            .init(
                id: "matrix.bat.full",
                deviceID: "d2",
                deviceName: "Keyboard",
                kind: .keyboard,
                percent: 100,
                threshold: 100,
                detail: "full"
            )
        )
    }

    private var peripheralConnected: IslandNoticePayload {
        .peripheralConnected(
            .init(
                id: "matrix.bat.connect",
                deviceID: "d3",
                deviceName: "Trackpad",
                kind: .trackpad,
                percent: 80,
                threshold: 0,
                detail: "connected"
            )
        )
    }

    private func makeSlots(
        exclusive: Bool = false,
        meetingOn: Bool = false,
        media: Bool = false,
        focus: Bool = false,
        secondary: IslandNoticePayload? = nil
    ) -> IslandNoticeSlots {
        var slots = IslandNoticeSlots(focusResident: focus, mediaResident: media)
        if exclusive {
            slots.primary = self.exclusive
        } else if meetingOn {
            slots.primary = meeting
        }
        slots.secondary = secondary
        return slots
    }

    // MARK: - 1. resolvedLayout 真值表（会议 × 播放 × 专注 × C）

    /// 16 格穷举 + 独占压过一切；与 `IslandNoticeSlotPolicy.resolvedLayout` 一一对应。
    func test_islandNoticeLayoutMatrix_resolvedLayoutTruthTable() {
        struct Row {
            let name: String
            let exclusive: Bool
            let meeting: Bool
            let media: Bool
            let focus: Bool
            let hasC: Bool
            let expected: IslandNoticeLayout
        }

        let c = copy
        let rows: [Row] = {
            var list: [Row] = []
            for exclusive in [false, true] {
                for meetingOn in [false, true] {
                    for media in [false, true] {
                        for focus in [false, true] {
                            for hasC in [false, true] {
                                let name = [
                                    exclusive ? "A" : "-",
                                    meetingOn ? "M" : "-",
                                    media ? "P" : "-",
                                    focus ? "F" : "-",
                                    hasC ? "C" : "-"
                                ].joined()
                                let expected: IslandNoticeLayout
                                if exclusive {
                                    expected = .fullNotice(self.exclusive)
                                } else if meetingOn {
                                    if hasC {
                                        expected = .dual(left: .notice(meeting), right: .notice(c))
                                    } else if focus {
                                        expected = .dual(left: .notice(meeting), right: .focus)
                                    } else {
                                        expected = .fullNotice(meeting)
                                    }
                                } else if media {
                                    if hasC {
                                        expected = .dual(left: .media, right: .notice(c))
                                    } else if focus {
                                        expected = .dual(left: .media, right: .focus)
                                    } else {
                                        expected = .fullMedia
                                    }
                                } else if hasC {
                                    if focus {
                                        expected = .dual(left: .focus, right: .notice(c))
                                    } else {
                                        expected = .fullNotice(c)
                                    }
                                } else if focus {
                                    expected = .fullFocus
                                } else {
                                    expected = .empty
                                }
                                list.append(
                                    Row(
                                        name: name,
                                        exclusive: exclusive,
                                        meeting: meetingOn,
                                        media: media,
                                        focus: focus,
                                        hasC: hasC,
                                        expected: expected
                                    )
                                )
                            }
                        }
                    }
                }
            }
            return list
        }()

        XCTAssertEqual(rows.count, 32, "A×会议×播放×专注×C 应为 32 格")

        for row in rows {
            let slots = makeSlots(
                exclusive: row.exclusive,
                meetingOn: row.meeting,
                media: row.media,
                focus: row.focus,
                secondary: row.hasC ? c : nil
            )
            XCTAssertEqual(
                slots.resolvedLayout,
                row.expected,
                "真值表失败: \(row.name)"
            )
            // dual 一律 dualFlush；独占/单独会议满岛才抬会议翼壳。
            switch row.expected {
            case .dual:
                XCTAssertTrue(slots.usesDualFlushChrome, "dual 须 dualFlush: \(row.name)")
                XCTAssertFalse(slots.anyUsesNotchWingChrome, "dual 禁会议翼宽: \(row.name)")
            case .fullNotice(let p) where p.displayLane == .exclusive || p.displayLane == .primary:
                XCTAssertTrue(slots.anyUsesNotchWingChrome, "满岛 A/会议须翼壳: \(row.name)")
                XCTAssertFalse(slots.usesDualFlushChrome, "满岛 A/会议非 dualFlush: \(row.name)")
            case .fullNotice(let p) where p.usesDualFlushSoloChrome:
                XCTAssertTrue(slots.usesDualFlushChrome, "RAM/进程结束单独须 dualFlush: \(row.name)")
            case .fullMedia, .fullFocus, .empty:
                XCTAssertFalse(slots.usesDualFlushChrome, "\(row.name)")
                XCTAssertFalse(slots.anyUsesNotchWingChrome, "\(row.name)")
            default:
                break
            }
        }
    }

    // MARK: - 2. C 盖右翼专注再恢复（会议左 / 播放左）

    func test_islandNoticeLayoutMatrix_cCoversRightFocusThenRestores() {
        // 播放 + 专注
        let mediaFocus = IslandNoticeSlots(focusResident: true, mediaResident: true)
        XCTAssertEqual(
            mediaFocus.resolvedLayout,
            .dual(left: .media, right: .focus)
        )
        let withCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: mediaFocus)
        XCTAssertEqual(
            withCopy?.resolvedLayout,
            .dual(left: .media, right: .notice(copy))
        )
        XCTAssertTrue(withCopy?.focusResident == true)
        let restored = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: withCopy!)
        XCTAssertEqual(
            restored.resolvedLayout,
            .dual(left: .media, right: .focus)
        )

        // 会议 + 专注
        let meetingFocus = IslandNoticeSlotPolicy.applying(
            incoming: meeting,
            to: IslandNoticeSlots(focusResident: true)
        )!
        XCTAssertEqual(
            meetingFocus.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus)
        )
        let meetingCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: meetingFocus)!
        XCTAssertEqual(
            meetingCopy.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy))
        )
        let meetingRestored = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: meetingCopy)
        XCTAssertEqual(
            meetingRestored.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus)
        )
    }

    // MARK: - 3. 全部 tip 契约（lane / 自动收 / chrome / 设置中展开）

    /// 穷尽 `IslandNoticePayload` 每一 case；新增 case 时本 switch 编译失败。
    func test_islandNoticeLayoutMatrix_everyPayloadContract() {
        struct Expect {
            let lane: IslandNoticeDisplayLane
            let autoDismiss: Bool
            let keepsExpanded: Bool
            let expandsInSettings: Bool
            let notchWing: Bool
            let dualFlushSolo: Bool
            let rightOrb: Bool
            let holdHover: Bool
        }

        func expect(for payload: IslandNoticePayload) -> Expect {
            // 与生产契约对齐的穷尽表；改 tip 规则时改这里。
            switch payload {
            case .colorPickTip, .ocrSelectTip:
                return Expect(
                    lane: .exclusive,
                    autoDismiss: false,
                    keepsExpanded: true,
                    expandsInSettings: false,
                    notchWing: true,
                    dualFlushSolo: false,
                    rightOrb: false,
                    holdHover: false
                )
            case .meetingLead:
                return Expect(
                    lane: .primary,
                    autoDismiss: false,
                    keepsExpanded: true,
                    expandsInSettings: false,
                    notchWing: true,
                    dualFlushSolo: false,
                    rightOrb: false,
                    holdHover: true
                )
            case .ramPressure, .processEnded:
                return Expect(
                    lane: .secondary,
                    autoDismiss: true,
                    keepsExpanded: true,
                    expandsInSettings: true,
                    notchWing: false,
                    dualFlushSolo: true,
                    rightOrb: false,
                    holdHover: true
                )
            case .clipboardCaptureHint(let id, _, _):
                let isCopy = id.hasPrefix("copy.")
                return Expect(
                    lane: .secondary,
                    autoDismiss: true,
                    keepsExpanded: isCopy,
                    expandsInSettings: true,
                    notchWing: false,
                    dualFlushSolo: false,
                    rightOrb: isCopy,
                    // 「已复制」动效结束即收，不悬停续命；其它剪贴板 hint 仍保活。
                    holdHover: !isCopy
                )
            case .moveReminder, .aiUsageAlert,
                 .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
                 .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged:
                return Expect(
                    lane: .secondary,
                    autoDismiss: true,
                    keepsExpanded: true,
                    expandsInSettings: true,
                    notchWing: true,
                    dualFlushSolo: false,
                    rightOrb: false,
                    holdHover: true
                )
            }
        }

        let macCharging = IslandNoticePayload.macBatteryCharging(
            .init(id: "mac.ch", kind: .charging, percent: 60, threshold: 0, detail: "c")
        )
        let macLow = IslandNoticePayload.macBatteryLow(
            .init(id: "mac.lo", kind: .low, percent: 12, threshold: 20, detail: "l")
        )
        let macFull = IslandNoticePayload.macBatteryFull(
            .init(id: "mac.fu", kind: .full, percent: 100, threshold: 100, detail: "f")
        )
        let macUnplug = IslandNoticePayload.macBatteryUnplugged(
            .init(id: "mac.up", kind: .unplugged, percent: 64, threshold: 0, detail: "u")
        )

        let samples: [IslandNoticePayload] = [
            exclusive,
            ocr,
            meeting,
            copy,
            .clipboardCaptureHint(id: "paste.hint", text: "x", symbol: "doc"),
            move,
            ai,
            ram,
            processEnded,
            peripheralLow,
            peripheralFull,
            peripheralConnected,
            macCharging,
            macLow,
            macFull,
            macUnplug
        ]

        // 16 个样本覆盖全部 case 族；clipboard 两种（copy / 非 copy）；本机电池四态。
        XCTAssertEqual(samples.count, 16)

        for payload in samples {
            let e = expect(for: payload)
            XCTAssertEqual(payload.displayLane, e.lane, payload.sourceTag)
            XCTAssertEqual(payload.autoDismissNanoseconds != nil, e.autoDismiss, payload.sourceTag)
            XCTAssertEqual(payload.keepsExpandedWithoutHover, e.keepsExpanded, payload.sourceTag)
            XCTAssertEqual(payload.expandsDuringSettingsSession, e.expandsInSettings, payload.sourceTag)
            XCTAssertEqual(payload.usesNotchWingChrome, e.notchWing, payload.sourceTag)
            XCTAssertEqual(payload.usesDualFlushSoloChrome, e.dualFlushSolo, payload.sourceTag)
            XCTAssertEqual(payload.usesNotchRightOrbChrome, e.rightOrb, payload.sourceTag)
            XCTAssertEqual(payload.holdsWhileHovering, e.holdHover, payload.sourceTag)
            XCTAssertFalse(payload.usesDualFlushTrailingOnlyChrome, payload.sourceTag)
            XCTAssertFalse(payload.usesShortBelowNotchChrome, payload.sourceTag)
            // expandsDuringSettingsSession 与「有自动收」绑定。
            XCTAssertEqual(
                payload.expandsDuringSettingsSession,
                payload.autoDismissNanoseconds != nil,
                payload.sourceTag
            )
        }

        // 单独 RAM / 进程结束：紧凑双翼；单独已复制：圆岛。
        XCTAssertTrue(IslandNoticeSlots(secondary: ram).usesDualFlushCompactWings)
        XCTAssertTrue(IslandNoticeSlots(secondary: processEnded).usesDualFlushCompactWings)
        XCTAssertFalse(IslandNoticeSlots(secondary: copy).usesDualFlushCompactWings)
        XCTAssertTrue(IslandNoticeSlots(secondary: copy).anyUsesNotchRightOrbChrome)
        // 与播放/专注并排时，「已复制」不走整岛圆岛 chrome。
        var copyWithFocus = IslandNoticeSlots(focusResident: true)
        copyWithFocus.secondary = copy
        XCTAssertFalse(copyWithFocus.anyUsesNotchRightOrbChrome)
        var copyWithMedia = IslandNoticeSlots(mediaResident: true)
        copyWithMedia.secondary = copy
        XCTAssertFalse(copyWithMedia.anyUsesNotchRightOrbChrome)
    }

    // MARK: - 4. 投递 / 撤回 / FIFO / 独占

    func test_islandNoticeLayoutMatrix_applyingDismissingAndFIFO() {
        // 独占清 C 队列，并挡住后续 C / 会议
        var withQueue = IslandNoticeSlotPolicy.applying(incoming: copy, to: IslandNoticeSlots())!
        withQueue = IslandNoticeSlotPolicy.applying(incoming: move, to: withQueue)!
        XCTAssertEqual(withQueue.secondary?.id, copy.id)
        XCTAssertEqual(withQueue.secondaryQueue.count, 1)

        let afterA = IslandNoticeSlotPolicy.applying(incoming: exclusive, to: withQueue)!
        XCTAssertEqual(afterA.primary?.id, exclusive.id)
        XCTAssertNil(afterA.secondary)
        XCTAssertTrue(afterA.secondaryQueue.isEmpty)
        XCTAssertEqual(afterA.resolvedLayout, .fullNotice(exclusive))

        XCTAssertNil(IslandNoticeSlotPolicy.applying(incoming: copy, to: afterA))
        XCTAssertNil(IslandNoticeSlotPolicy.applying(incoming: meeting, to: afterA))

        // OCR 同样是独占
        XCTAssertEqual(ocr.displayLane, .exclusive)
        let afterOCR = IslandNoticeSlotPolicy.applying(incoming: ocr, to: IslandNoticeSlots())!
        XCTAssertEqual(afterOCR.resolvedLayout, .fullNotice(ocr))

        // FIFO：三条 C，同时只一条；dismiss 出队
        let first = IslandNoticeSlotPolicy.applying(incoming: ai, to: IslandNoticeSlots())!
        let second = IslandNoticeSlotPolicy.applying(incoming: peripheralLow, to: first)!
        let third = IslandNoticeSlotPolicy.applying(incoming: ram, to: second)!
        XCTAssertEqual(third.secondary?.id, ai.id)
        XCTAssertEqual(third.secondaryQueue.map(\.id), [peripheralLow.id, ram.id])

        let afterFirst = IslandNoticeSlotPolicy.dismissing(id: ai.id, from: third)
        XCTAssertEqual(afterFirst.secondary?.id, peripheralLow.id)
        XCTAssertEqual(afterFirst.secondaryQueue.map(\.id), [ram.id])

        let afterSecond = IslandNoticeSlotPolicy.dismissing(id: peripheralLow.id, from: afterFirst)
        XCTAssertEqual(afterSecond.secondary?.id, ram.id)
        XCTAssertTrue(afterSecond.secondaryQueue.isEmpty)

        // 同 id 刷新不入队
        let refreshed = IslandNoticeSlotPolicy.applying(incoming: ram, to: afterSecond)!
        XCTAssertEqual(refreshed.secondary?.id, ram.id)
        XCTAssertTrue(refreshed.secondaryQueue.isEmpty)

        // dismiss 全部：保留常驻旗标
        var flagged = IslandNoticeSlots(focusResident: true, mediaResident: true)
        flagged = IslandNoticeSlotPolicy.applying(incoming: meeting, to: flagged)!
        flagged = IslandNoticeSlotPolicy.applying(incoming: copy, to: flagged)!
        let cleared = IslandNoticeSlotPolicy.dismissing(id: nil, from: flagged)
        XCTAssertNil(cleared.primary)
        XCTAssertNil(cleared.secondary)
        XCTAssertTrue(cleared.secondaryQueue.isEmpty)
        XCTAssertTrue(cleared.focusResident)
        XCTAssertTrue(cleared.mediaResident)
        XCTAssertEqual(cleared.resolvedLayout, .dual(left: .media, right: .focus))

        // 会议 rank 高于久坐；久坐不能盖会议 primary（久坐是 C，进 secondary）
        let meetingSlots = IslandNoticeSlotPolicy.applying(incoming: meeting, to: IslandNoticeSlots())!
        let withMove = IslandNoticeSlotPolicy.applying(incoming: move, to: meetingSlots)!
        XCTAssertEqual(withMove.primary?.id, meeting.id)
        XCTAssertEqual(withMove.secondary?.id, move.id)
    }

    // MARK: - 5. 会议盖播放 + 三常驻与 C

    func test_islandNoticeLayoutMatrix_meetingCoversMediaAndTripleResidents() {
        // 会议 + 播放 → 满岛会议，mediaResident 仍亮
        var meetingMedia = IslandNoticeSlots(mediaResident: true)
        meetingMedia = IslandNoticeSlotPolicy.applying(incoming: meeting, to: meetingMedia)!
        XCTAssertTrue(meetingMedia.mediaResident)
        XCTAssertEqual(meetingMedia.resolvedLayout, .fullNotice(meeting))

        // 会议 + 播放 + 专注 → 左会议右专注（播放仍被盖）
        meetingMedia.focusResident = true
        XCTAssertEqual(
            meetingMedia.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus)
        )

        // 再来 C → 左会议右 C；撤 C 后右翼回专注
        let withC = IslandNoticeSlotPolicy.applying(incoming: copy, to: meetingMedia)!
        XCTAssertEqual(
            withC.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy))
        )
        let back = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: withC)
        XCTAssertEqual(
            back.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus)
        )
        XCTAssertTrue(back.mediaResident)

        // 播放 + 专注 + C 队列：C 完后回左播放右专注
        var mediaFocus = IslandNoticeSlots(focusResident: true, mediaResident: true)
        mediaFocus = IslandNoticeSlotPolicy.applying(incoming: copy, to: mediaFocus)!
        mediaFocus = IslandNoticeSlotPolicy.applying(incoming: move, to: mediaFocus)!
        XCTAssertEqual(mediaFocus.secondary?.id, copy.id)
        XCTAssertEqual(mediaFocus.secondaryQueue.map(\.id), [move.id])
        let afterCopy = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: mediaFocus)
        XCTAssertEqual(
            afterCopy.resolvedLayout,
            .dual(left: .media, right: .notice(move))
        )
        let afterMove = IslandNoticeSlotPolicy.dismissing(id: move.id, from: afterCopy)
        XCTAssertEqual(
            afterMove.resolvedLayout,
            .dual(left: .media, right: .focus)
        )
    }

    // MARK: - 6. 设置会话强制展开策略（瞬时 tip vs 会议）

    func test_islandNoticeLayoutMatrix_settingsSessionExpandPolicy() {
        // 有 autoDismiss 的 tip：设置中仍 force expand
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: true,
                pointerOverSettings: true,
                expandsDuringSettingsSession: true
            )
        )
        // 会议等无 autoDismiss：设置中不 force
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: true,
                pointerOverSettings: false,
                expandsDuringSettingsSession: false
            )
        )
        // 已展开则不再 force
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: true,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: false,
                expandsDuringSettingsSession: true
            )
        )
        // 瞬时 tip：即使 pointer 在设置上，仍 force
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: true,
                pointerOverSettings: true,
                expandsDuringSettingsSession: true
            )
        )
        // 非瞬时、未挡设置、指针不在设置 → force
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: false,
                expandsDuringSettingsSession: false
            )
        )
        // keepsExpanded=false → 永不 force
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: false,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: false,
                expandsDuringSettingsSession: true
            )
        )
    }

    // MARK: - 7. 产品权重阶梯（命名规则）

    func test_islandNoticeLayoutMatrix_priorityLadderNamedRules() {
        // 取色/框选/会议 > 播放 > 专注 > C
        let mediaFocus = IslandNoticeSlots(focusResident: true, mediaResident: true)
        XCTAssertEqual(mediaFocus.resolvedLayout, .dual(left: .media, right: .focus), "播放左、专注右")

        var meetingOverMedia = IslandNoticeSlots(mediaResident: true)
        meetingOverMedia = IslandNoticeSlotPolicy.applying(incoming: meeting, to: meetingOverMedia)!
        XCTAssertEqual(meetingOverMedia.resolvedLayout, .fullNotice(meeting), "会议盖播放满岛")

        var meetingFocus = meetingOverMedia
        meetingFocus.focusResident = true
        XCTAssertEqual(
            meetingFocus.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus),
            "会议+专注：左会议右专注，播放仍被盖"
        )

        let withC = IslandNoticeSlotPolicy.applying(incoming: copy, to: meetingFocus)!
        XCTAssertEqual(
            withC.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy)),
            "C 盖右翼专注"
        )

        let exclusiveOverAll = IslandNoticeSlotPolicy.applying(
            incoming: exclusive,
            to: withC
        )!
        XCTAssertEqual(exclusiveOverAll.resolvedLayout, .fullNotice(exclusive), "取色独占一切 tip")
        XCTAssertTrue(exclusiveOverAll.focusResident)
        XCTAssertTrue(exclusiveOverAll.mediaResident)
    }

    // MARK: - 8. 每一种 C 都能盖右翼专注，撤后专注回右

    func test_islandNoticeLayoutMatrix_everySecondaryCoversRightFocus() {
        let secondaries: [IslandNoticePayload] = [
            copy, move, ai, ram, processEnded, peripheralLow, peripheralFull, peripheralConnected
        ]
        XCTAssertEqual(secondaries.count, 8)

        for tip in secondaries {
            XCTAssertEqual(tip.displayLane, .secondary, tip.sourceTag)

            // 播放 + 专注 + C
            var mediaFocus = IslandNoticeSlots(focusResident: true, mediaResident: true)
            mediaFocus = IslandNoticeSlotPolicy.applying(incoming: tip, to: mediaFocus)!
            XCTAssertEqual(
                mediaFocus.resolvedLayout,
                .dual(left: .media, right: .notice(tip)),
                "播放左 C 右: \(tip.sourceTag)"
            )
            XCTAssertTrue(mediaFocus.focusResident, tip.sourceTag)
            let mediaRestored = IslandNoticeSlotPolicy.dismissing(id: tip.id, from: mediaFocus)
            XCTAssertEqual(
                mediaRestored.resolvedLayout,
                .dual(left: .media, right: .focus),
                "撤 C 后专注回右: \(tip.sourceTag)"
            )

            // 会议 + 专注 + C
            var meetingFocus = IslandNoticeSlotPolicy.applying(
                incoming: meeting,
                to: IslandNoticeSlots(focusResident: true)
            )!
            meetingFocus = IslandNoticeSlotPolicy.applying(incoming: tip, to: meetingFocus)!
            XCTAssertEqual(
                meetingFocus.resolvedLayout,
                .dual(left: .notice(meeting), right: .notice(tip)),
                "会议左 C 右: \(tip.sourceTag)"
            )
            let meetingRestored = IslandNoticeSlotPolicy.dismissing(id: tip.id, from: meetingFocus)
            XCTAssertEqual(
                meetingRestored.resolvedLayout,
                .dual(left: .notice(meeting), right: .focus),
                "撤 C 后会议右回专注: \(tip.sourceTag)"
            )

            // 仅专注 + C → 左专注右 C（C 不占左）
            var focusOnly = IslandNoticeSlots(focusResident: true)
            focusOnly = IslandNoticeSlotPolicy.applying(incoming: tip, to: focusOnly)!
            XCTAssertEqual(
                focusOnly.resolvedLayout,
                .dual(left: .focus, right: .notice(tip)),
                "无 B 时专注左 C 右: \(tip.sourceTag)"
            )
        }
    }

    // MARK: - 9. C 有 B 时永不占左翼；翼宽：单独紧凑 / 并排标准

    func test_islandNoticeLayoutMatrix_cPlacementAndWingWidths() {
        for tip in [ram, processEnded, copy, move, ai, peripheralLow] {
            // 有播放：左必为 media
            var media = IslandNoticeSlots(mediaResident: true)
            media = IslandNoticeSlotPolicy.applying(incoming: tip, to: media)!
            if case .dual(let left, let right) = media.resolvedLayout {
                XCTAssertEqual(left, .media, tip.sourceTag)
                XCTAssertEqual(right, .notice(tip), tip.sourceTag)
            } else {
                XCTFail("应为 dual: \(tip.sourceTag)")
            }

            // 有会议：左必为会议
            var meet = IslandNoticeSlotPolicy.applying(incoming: meeting, to: IslandNoticeSlots())!
            meet = IslandNoticeSlotPolicy.applying(incoming: tip, to: meet)!
            if case .dual(let left, let right) = meet.resolvedLayout {
                XCTAssertEqual(left, .notice(meeting), tip.sourceTag)
                XCTAssertEqual(right, .notice(tip), tip.sourceTag)
            } else {
                XCTFail("应为 dual: \(tip.sourceTag)")
            }
        }

        // RAM / 进程结束：单独 = 紧凑翼；与播放并排 = 标准翼
        let soloRAM = IslandNoticeSlots(secondary: ram)
        XCTAssertTrue(soloRAM.usesDualFlushCompactWings)
        XCTAssertEqual(soloRAM.dualFlushWingWidth, IslandChrome.dualFlushCompactWingWidth)

        var ramWithMedia = IslandNoticeSlots(mediaResident: true)
        ramWithMedia = IslandNoticeSlotPolicy.applying(incoming: ram, to: ramWithMedia)!
        XCTAssertTrue(ramWithMedia.usesDualFlushChrome)
        XCTAssertFalse(ramWithMedia.usesDualFlushCompactWings)
        XCTAssertEqual(ramWithMedia.dualFlushWingWidth, IslandChrome.dualFlushLeftWingWidth)

        let soloProcess = IslandNoticeSlots(secondary: processEnded)
        XCTAssertTrue(soloProcess.usesDualFlushCompactWings)
        var processWithFocus = IslandNoticeSlots(focusResident: true)
        processWithFocus = IslandNoticeSlotPolicy.applying(incoming: processEnded, to: processWithFocus)!
        XCTAssertFalse(processWithFocus.usesDualFlushCompactWings)
    }
}
