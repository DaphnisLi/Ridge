import CoreGraphics
import Foundation

/// # ⚠ LOCKED — 产品固定契约（未经用户明确授权禁止修改）
///
/// 本文件是 Ridge **已确认不会改**的产品 / 回归契约的**唯一代码落点**。
/// 数值、分支、档位成员若要动：Agent **必须先问用户并获得本对话内明确授权**，否则只能改调用方或补测试。
///
/// 询问模板：「需要改 `LockedInvariants.<符号>`，原因是…，是否授权修改锁定文件？」
///
/// 对应规则：`.cursor/rules/locked-invariants.mdc`（alwaysApply）。
/// 对应回归：`docs/REGRESSION_CATALOG.md` recurring 表；自动化 `test_lockedInvariants_*`。
///
/// 调用方（`IslandExpandedPanelPolicy` / `IslandChrome` / Notice / Focus）只做转发或壳层，
/// **禁止**在调用方再抄一套同义分支，否则锁会失效。
enum LockedInvariants {
    /// 文件身份；测试钉死，防止整文件被换皮却漏测。扩分区须 bump。
    static let lockID = "ridge.locked-invariants.v2"

    // MARK: - island-hover-retention / media-compact / shelf-magnetic

    /// 展开保展开、误缩护栏、收起悬停仅刘海、拖文件接近区。
    enum HoverRetention {
        /// 相对当前尺寸，单边缩小超过此值视为「误缩」。
        static let accidentalShrinkThreshold: CGFloat = 28
        /// 内容区纵滑结束后仍保展开的宽限（秒）。
        static let contentScrollHoldGrace: TimeInterval = 0.55
        /// 展开保展开：面板外扩。
        static let retentionPanelPad: CGFloat = 16
        /// 展开保展开：底边额外外扩（纵滑不易误收）。
        static let retentionPanelBottomExtra: CGFloat = 20
        /// 收起态悬停展开：刘海外扩。
        static let hoverExpandNotchPad: CGFloat = 4
        /// 收起态可点水平外扩（右翼 morph 贴边）。
        static let collapsedInteractivePadX: CGFloat = 32
        /// 收起态可点竖直外扩。
        static let collapsedInteractivePadY: CGFloat = 10
        /// 拖文件接近区相对刘海左右外扩；宽度跟刘海。
        static let fileDragApproachHorizontalOutset: CGFloat = 0
        /// 接近区总高度至少为刘海高的倍数。
        static let fileDragApproachMinHeightInNotches: CGFloat = 3
        /// 未入舱松手后禁止普通悬停再开。
        static let postFileDragHoverSuppress: TimeInterval = 0.55

        /// Preference 未到 / 宽矮选时 / tip 压矮：保展开不得矮于此。
        static func expandedRetentionFloor(notch: CGSize) -> CGSize {
            CGSize(
                width: max(notch.width + 120, 320),
                height: max(notch.height + 120, 160)
            )
        }

        /// 展开态保展开尺寸：最终 ≥ max(首选, 当前面板, floor)。可见 panel 可矮，仅热区抬高。
        static func resolvedRetentionPanelSize(
            panel: CGSize,
            stable: CGSize,
            notch: CGSize,
            isExpanded: Bool
        ) -> CGSize {
            let preferred: CGSize = {
                if shouldPreferStableRetention(
                    panel: panel,
                    stable: stable,
                    notch: notch,
                    isExpanded: isExpanded
                ) {
                    return stable
                }
                guard isExpanded else { return panel }
                if isCollapsedSizedWhileExpanded(panel: panel, notch: notch, isExpanded: true) {
                    let floor = expandedRetentionFloor(notch: notch)
                    return CGSize(
                        width: max(panel.width, floor.width),
                        height: max(panel.height, floor.height)
                    )
                }
                return panel
            }()
            guard isExpanded else { return preferred }
            let floored = expandedRetentionFloor(notch: notch)
            return CGSize(
                width: max(preferred.width, panel.width, floored.width),
                height: max(preferred.height, panel.height, floored.height)
            )
        }

        static func shouldPreferStableRetention(
            panel: CGSize,
            stable: CGSize,
            notch: CGSize,
            isExpanded: Bool,
            heightSlop: CGFloat = 40,
            widthSlop: CGFloat = 80
        ) -> Bool {
            guard isExpanded else { return false }
            guard stable.width > notch.width + 8, stable.height > notch.height + 8 else {
                return false
            }
            if isCollapsedSizedWhileExpanded(panel: panel, notch: notch, isExpanded: true) {
                return true
            }
            if isTransientShortPanel(panel, notch: notch) {
                return true
            }
            return panel.height + heightSlop < stable.height
                || panel.width + widthSlop < stable.width
        }

        static func isCollapsedSizedWhileExpanded(
            panel: CGSize,
            notch: CGSize,
            isExpanded: Bool,
            slop: CGFloat = 8
        ) -> Bool {
            guard isExpanded else { return false }
            if IslandChrome.isNotchRightOrbPanelSize(panel) { return false }
            return panel.width <= notch.width + slop && panel.height <= notch.height + slop
        }

        /// 短 tip / 选时矮框：可见可矮，禁止写入 lastStable。
        static func isTransientShortPanel(
            _ panel: CGSize,
            notch: CGSize,
            maxHeightAboveNotch: CGFloat = 48,
            maxWidthAboveNotch: CGFloat = 140
        ) -> Bool {
            panel.height <= notch.height + maxHeightAboveNotch
                || panel.width <= notch.width + maxWidthAboveNotch
        }

        static func shouldApplyMeasuredSize(
            current: CGSize,
            measured: CGSize,
            isExpanded: Bool,
            allowShrink: Bool,
            shrinkThreshold: CGFloat = accidentalShrinkThreshold
        ) -> Bool {
            guard abs(measured.width - current.width) > 0.5
                || abs(measured.height - current.height) > 0.5
            else {
                return false
            }
            guard isExpanded, !allowShrink else { return true }
            let shrinkW = current.width - measured.width
            let shrinkH = current.height - measured.height
            if shrinkW > shrinkThreshold || shrinkH > shrinkThreshold {
                if isWingToShortTipResize(
                    current: current,
                    measured: measured,
                    shrinkH: shrinkH,
                    shrinkThreshold: shrinkThreshold
                ) {
                    return true
                }
                return false
            }
            return true
        }

        static func isWingToShortTipResize(
            current: CGSize,
            measured: CGSize,
            shrinkH: CGFloat,
            shrinkThreshold: CGFloat = accidentalShrinkThreshold
        ) -> Bool {
            guard shrinkH <= shrinkThreshold else { return false }
            if IslandChrome.isNotchRightOrbPanelSize(measured) { return true }
            return measured.height + 1 >= current.height
        }

        static func retentionFrame(
            notchFrame: CGRect,
            panelFrame: CGRect,
            expanded: Bool,
            notchPad: CGFloat = hoverExpandNotchPad,
            panelPad: CGFloat = retentionPanelPad,
            panelBottomExtra: CGFloat = retentionPanelBottomExtra
        ) -> CGRect {
            let notchHit = hoverExpandFrame(notchFrame: notchFrame, notchPad: notchPad)
            if !expanded {
                _ = panelFrame
                return notchHit
            }
            let padded = panelFrame.insetBy(dx: -panelPad, dy: -panelPad)
            let withBottom = CGRect(
                x: padded.origin.x,
                y: padded.origin.y - panelBottomExtra,
                width: padded.width,
                height: padded.height + panelBottomExtra
            )
            return withBottom.union(notchHit)
        }

        static func hoverExpandFrame(
            notchFrame: CGRect,
            notchPad: CGFloat = hoverExpandNotchPad
        ) -> CGRect {
            notchFrame.insetBy(dx: -notchPad, dy: -2)
        }

        static func collapsedInteractiveFrame(
            panelFrame: CGRect,
            notchFrame: CGRect
        ) -> CGRect {
            panelFrame
                .insetBy(dx: -collapsedInteractivePadX, dy: -collapsedInteractivePadY)
                .union(hoverExpandFrame(notchFrame: notchFrame))
        }

        static func isFileDragApproachEnabled(shelfEnabled: Bool, isFileDrag: Bool) -> Bool {
            shelfEnabled && isFileDrag
        }

        static func isMagneticStagingEnabled(
            shelfEnabled: Bool,
            magneticEnabled: Bool,
            isFileDrag: Bool
        ) -> Bool {
            shelfEnabled && magneticEnabled && isFileDrag
        }

        static func fileDragApproachFrame(
            notchFrame: CGRect,
            horizontalOutset: CGFloat = fileDragApproachHorizontalOutset,
            minHeightInNotches: CGFloat = fileDragApproachMinHeightInNotches
        ) -> CGRect {
            let notchH = max(notchFrame.height, 1)
            let targetH = max(notchH * minHeightInNotches, notchH)
            let bottomOutset = max(0, targetH - notchH)
            var zone = notchFrame.insetBy(dx: -horizontalOutset, dy: 0)
            zone.origin.y -= bottomOutset
            zone.size.height += bottomOutset
            return zone
        }

        static func shouldExpandCollapsedForPointer(
            mouse: CGPoint,
            notchFrame: CGRect,
            isFileDrag: Bool,
            fileDragApproachContainsMouse: Bool,
            hoverExpandSuppressed: Bool = false
        ) -> Bool {
            if isFileDrag {
                if fileDragApproachContainsMouse { return true }
                return hoverExpandFrame(notchFrame: notchFrame).contains(mouse)
            }
            if hoverExpandSuppressed { return false }
            return hoverExpandFrame(notchFrame: notchFrame).contains(mouse)
        }

        /// 右计时翼：禁止 compactHover 开媒体。
        static func shouldExpandCollapsedForMediaCompact(
            notchHover: Bool,
            pointerOverCompactPanel: Bool,
            mediaCompactVisible: Bool,
            hoverExpandSuppressed: Bool,
            pointerOverFocusTrailingWing: Bool = false
        ) -> Bool {
            if hoverExpandSuppressed { return false }
            if pointerOverFocusTrailingWing { return false }
            if notchHover { return true }
            return mediaCompactVisible && pointerOverCompactPanel
        }

        static func shouldForceCollapseAfterShelfFileDragMouseUp(
            hadShelfFileDragExpand: Bool,
            dropCompletedRecently: Bool,
            isExpanded: Bool,
            pointerInExpandedRetention: Bool
        ) -> Bool {
            hadShelfFileDragExpand
                && !dropCompletedRecently
                && isExpanded
                && !pointerInExpandedRetention
        }

        static func shouldHoldExpandForRecentScroll(
            lastScrollAt: Date?,
            now: Date = Date(),
            grace: TimeInterval = contentScrollHoldGrace
        ) -> Bool {
            guard let lastScrollAt else { return false }
            return now.timeIntervalSince(lastScrollAt) < grace
        }

        static func retentionContainsMidLowerPoint(
            notchFrame: CGRect,
            panelFrame: CGRect,
            expanded: Bool
        ) -> Bool {
            let frame = retentionFrame(
                notchFrame: notchFrame,
                panelFrame: panelFrame,
                expanded: expanded
            )
            let midLower = CGPoint(
                x: panelFrame.midX,
                y: panelFrame.minY + panelFrame.height * 0.25
            )
            return frame.contains(midLower)
        }
    }

    // MARK: - island-notice-behavior / shelf-copied-notice-miss / settings-session-swallows-transient-notice

    enum Notice {
        /// 唯一瞬时通知 widget id；禁止再注册第二个 `systemTransient`。
        static let widgetID = "system.islandNotice"
        /// 空态 id。
        static let emptyWidgetID = "system.empty"
        /// 非专注 C 瞬时 tip 统一停留（纳秒）。
        static let standardDisplayNanoseconds: UInt64 = 3_000_000_000
        /// 悬停 / 设置挡轮询间隔。
        static let pollNanoseconds: UInt64 = 100_000_000

        /// 仅「收起会话 + 设计 sticky」挡程序 tip；测试台 / 普通设置不挡。
        static func settingsBlocksProgrammaticNoticeExpand(
            sessionActive: Bool,
            livePreview: Bool,
            designSticky: Bool
        ) -> Bool {
            sessionActive && !livePreview && designSticky
        }

        static func shouldForceStickyNoticeExpand(
            isExpanded: Bool,
            keepsExpandedWithoutHover: Bool,
            settingsSessionBlocksIslandTips: Bool,
            pointerOverSettings: Bool,
            expandsDuringSettingsSession: Bool = false
        ) -> Bool {
            guard keepsExpandedWithoutHover, !isExpanded else { return false }
            if expandsDuringSettingsSession { return true }
            if settingsSessionBlocksIslandTips { return false }
            if pointerOverSettings { return false }
            return true
        }

        static func shouldKeepExpandedAfterNoticeEnd(
            hovering: Bool,
            noticeFullyGone: Bool,
            allowsHoverExpand: Bool
        ) -> Bool {
            hovering && noticeFullyGone && allowsHoverExpand
        }

        static func isNoticeFullyGone(currentIsNil: Bool, isTransientNoticePage: Bool) -> Bool {
            currentIsNil && !isTransientNoticePage
        }

        static func shouldWaitForSettingsUnblock(
            expandsDuringSettingsSession: Bool,
            settingsBlocksExpand: Bool
        ) -> Bool {
            !expandsDuringSettingsSession && settingsBlocksExpand
        }

        static func shouldWaitForHoverEnd(holdWhileHovering: Bool, isHovering: Bool) -> Bool {
            holdWhileHovering && isHovering
        }

        static func shouldDismissNow(
            expandsDuringSettingsSession: Bool,
            settingsBlocksExpand: Bool,
            holdWhileHovering: Bool,
            isHovering: Bool,
            elapsedNanoseconds: UInt64,
            displayNanoseconds: UInt64
        ) -> Bool {
            if shouldWaitForSettingsUnblock(
                expandsDuringSettingsSession: expandsDuringSettingsSession,
                settingsBlocksExpand: settingsBlocksExpand
            ) {
                return false
            }
            guard elapsedNanoseconds >= displayNanoseconds else { return false }
            if shouldWaitForHoverEnd(holdWhileHovering: holdWhileHovering, isHovering: isHovering) {
                return false
            }
            return true
        }
    }

    // MARK: - island-focus-steal

    enum Focus {
        static let shouldActivateAppWhenDisablingClickThrough = false
        static let shouldActivateAppOnExpand = false
        static let shouldResignKeyWhenEnablingClickThrough = true
        static let shouldActivateAppOnPlainIslandMouseDown = false
        static let shouldMakeKeyOnPlainIslandMouseDown = true
    }

    // MARK: - island-chrome-double-padding / tip-outline / shelf-copied orb

    enum Chrome {
        /// 内容相对面板左右 / 底（禁止内容根再叠一层）。
        static let contentHorizontal: CGFloat = 7
        static let preparedWingWidth: CGFloat = 98
        static let preparedPeripheralWingWidth: CGFloat = 78
        static let preparedNetworkLinkWingWidth: CGFloat = 84
        static let preparedFocusCompletedWingWidth: CGFloat = 120
        static let notchRightOrbDiameter: CGFloat = 32
        static let notchRightOrbGap: CGFloat = 2
        /// 「已复制」入场 + 定格；勿套默认 3s。
        static let notchRightOrbEntranceNanoseconds: UInt64 = 900_000_000
        static let notchRightOrbLingerNanoseconds: UInt64 = 500_000_000
        static var notchRightOrbAutoDismissNanoseconds: UInt64 {
            notchRightOrbEntranceNanoseconds + notchRightOrbLingerNanoseconds
        }
        /// dualFlush / 圆岛：壳层 inset 必须全 0（shelf-copied 全黑 / chrome 叠边）。
        static let dualFlushLeftWingWidth: CGFloat = 120
        static let dualFlushCompactWingWidth: CGFloat = 96
        static let dualFlushNotchUnderlap: CGFloat = 12
        static let dualFlushInsetTop: CGFloat = 0
        static let dualFlushInsetBottom: CGFloat = 0
        static let dualFlushInsetHorizontal: CGFloat = 0
        static let compactTipBottom: CGFloat = 4
    }

    // MARK: - island-priority-grades（档位成员；新能力须先问用户再改）

    enum PriorityGrade {
        /// A：取色 / 框选（独占）
        static let gradeAMembers = ["exclusive:colorPick", "exclusive:ocr"]
        /// B：会议 / 正在播放
        static let gradeBMembers = ["meeting", "mediaResident"]
        /// C：浏览器下载 / 专注计时（不是系统专注 tip）
        static let gradeCMembers = ["downloadResident", "focusResident"]
        /// D：瞬时 tip → 仅 `system.islandNotice`
        static let gradeDChannelID = Notice.widgetID
    }

    // MARK: - shelf-copied-notice-miss

    enum CopiedNotice {
        static let tipIDPrefix = "copy."
        static let widgetID = "builtin.copiedNotice"
        /// 同指纹去抖（秒）。
        static let dedupInterval: TimeInterval = 2.0
        /// 有自动收 → 设计 sticky 开着也必须投递（禁 ClipboardHistoryStore 提前 return）。
        static let mustDeliverDespiteDesignSticky = true
        /// 「已复制」不悬停续命。
        static let holdsWhileHovering = false
        /// dualFlush 行禁止 GeometryReader（fixedSize 下宽塌成全黑）。
        static let dualFlushForbidsGeometryReader = true

        static func isCopiedTipID(_ id: String) -> Bool {
            id.hasPrefix(tipIDPrefix)
        }
    }

    // MARK: - media-compact-not-resident

    enum Media {
        /// 媒体大面板非常驻：收岛即撤闸。
        static let expandedPanelIsResident = false
        static let focusTimerWidgetID = "builtin.focusTimer"
        static let mediaWidgetID = "builtin.media"

        /// 专注选时页打开时，禁止播放悬停/按住抢成媒体大面板。
        static func shouldBlockMediaExpand(focusIsPicking: Bool, activePageIsFocusTimer: Bool) -> Bool {
            focusIsPicking && activePageIsFocusTimer
        }

        /// 右计时翼悬停：禁开媒体（留给 morph）。
        static func shouldOpenMediaOnTrailingFocusWing() -> Bool { false }
    }

    // MARK: - island-focus-steal / focus 终局 / 选时

    enum FocusTimer {
        static let widgetID = Media.focusTimerWidgetID
        /// 终局不因指针离开收岛。
        static func keepsExpandedWithoutHover(phaseIsCompleted: Bool) -> Bool {
            phaseIsCompleted
        }
        /// 终局预备高 = 刘海（禁再叠 compactTipBottom）。
        static let completedPanelHeightEqualsNotch = true
        /// 选时「正计时」整颗（图标+文案）同一热区。
        static let countUpButtonEntireCapsuleIsHitTarget = true
    }

    // MARK: - meeting-join / meeting-tip-after-join

    enum Meeting {
        /// 已入会场次禁止再 publish tip。
        static func shouldRejectRepublish(meetingID: String, dismissedAfterJoinID: String?) -> Bool {
            guard let dismissed = dismissedAfterJoinID else { return false }
            return meetingID == dismissed
        }

        /// 日历事件详情页 —— 点开不是会议室。
        static func isLikelyCalendarEventPage(host: String, path: String, absolute: String) -> Bool {
            let host = host.lowercased()
            let path = path.lowercased()
            let absolute = absolute.lowercased()
            if host.contains("calendar.google.com") { return true }
            if host.contains("google.com"), path.contains("/calendar") || absolute.contains("eid=") {
                return true
            }
            if host.contains("outlook.office.com")
                || host.contains("outlook.office365.com")
                || host.contains("outlook.live.com")
            {
                return true
            }
            if host.contains("icloud.com"), path.contains("calendar") { return true }
            if host == "aka.ms", path.contains("meettimes") { return false }
            return false
        }
    }

    // MARK: - island-notice-layout-matrix

    /// A > B > C > D；C 内下载 > 计时。实现与 `IslandNoticeSlotPolicy.resolvedLayout` 必须一致。
    enum LayoutMatrix {
        static func resolvedLayout(_ slots: IslandNoticeSlots) -> IslandNoticeLayout {
            if let primary = slots.primary, primary.displayLane == .exclusive {
                return .fullNotice(primary)
            }
            if let primary = slots.primary {
                if let secondary = slots.secondary {
                    return .dual(left: .notice(primary), right: .notice(secondary))
                }
                if slots.downloadResident {
                    return .dual(left: .notice(primary), right: .download)
                }
                if slots.focusResident {
                    return .dual(left: .notice(primary), right: .focus)
                }
                return .fullNotice(primary)
            }
            if slots.mediaResident {
                if let secondary = slots.secondary {
                    return .dual(left: .media, right: .notice(secondary))
                }
                if slots.downloadResident {
                    return .dual(left: .media, right: .download)
                }
                if slots.focusResident {
                    return .dual(left: .media, right: .focus)
                }
                return .fullMedia
            }
            if slots.downloadResident {
                if let secondary = slots.secondary {
                    return .dual(left: .download, right: .notice(secondary))
                }
                if slots.focusResident {
                    return .dual(left: .download, right: .focus)
                }
                return .fullDownload
            }
            if let secondary = slots.secondary {
                if slots.focusResident {
                    return .dual(left: .focus, right: .notice(secondary))
                }
                return .fullNotice(secondary)
            }
            if slots.focusResident {
                return .fullFocus
            }
            return .empty
        }
    }

    // MARK: - settings-preview / library-island-stage-stretch / tip-outline

    enum Preview {
        /// tip 必须 hugs；禁止拉满 library 宽把翼内容扯散。
        static let tipPreviewHugsContent = true
        /// 预览禁 `.disabled`（系统降透明度）；用 allowsHitTesting(false)。
        static let forbidDisabledModifier = true
        /// 真岛/预览 tip 外形：上直角下圆角。
        static let tipOutlineIsPanel = true
        /// 「已复制」预览为正圆。
        static let copiedOutlineIsCircle = true
        static let libraryWidth: CGFloat = 290
        static let tipBarHeight: CGFloat = 30
        static let tipPreviewMinHeight: CGFloat = 30

        static func outlineIsCircle(widgetID: String) -> Bool {
            widgetID == CopiedNotice.widgetID
        }

        static func tipMustHug(widgetID: String) -> Bool {
            // 控制台固定宽除外；其余 tip / 媒体待命等走 hugs 策略由调用方细化。
            _ = widgetID
            return tipPreviewHugsContent
        }
    }

    // MARK: - download / shelf 打开后 suppress

    enum Download {
        /// 点打开 / 访达后禁止悬停立刻掀面板。
        static let postOpenHoverSuppress: TimeInterval = 1.6
    }
}
