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
        XCTAssertTrue(
            IslandExpandedPanelPolicy.retentionContainsMidLowerPoint(
                notchFrame: notch,
                panelFrame: panel,
                expanded: true
            ),
            "大岛下半截必须仍在保展开区"
        )
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: true
        )
        let midLower = CGPoint(x: panel.midX, y: panel.minY + 40)
        XCTAssertTrue(frame.contains(midLower), "大岛下半截必须仍在保展开区")
    }

    /// Preference 未到 / 误报刘海尺寸时：保展开须抬到下限，中下点仍命中（「移动一半就收」）。
    func test_islandHoverRetention_expandedFloorKeepsMidLowerWhenPanelStillNotchSized() {
        let notchSize = CGSize(width: 179, height: 32)
        let notchFrame = CGRect(x: 400, y: 968, width: notchSize.width, height: notchSize.height)
        let compactPanel = CGSize(width: notchSize.width, height: notchSize.height)

        XCTAssertTrue(
            IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: compactPanel,
                notch: notchSize,
                isExpanded: true
            )
        )

        let resolved = IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: compactPanel,
            stable: .zero,
            notch: notchSize,
            isExpanded: true
        )
        let floor = IslandExpandedPanelPolicy.expandedRetentionFloor(notch: notchSize)
        XCTAssertGreaterThanOrEqual(resolved.height, floor.height)
        XCTAssertGreaterThanOrEqual(resolved.width, floor.width)
        XCTAssertGreaterThan(
            resolved.height,
            notchSize.height + 80,
            "展开保展开高须明显高于刘海，否则下移一半必出热区"
        )

        // 贴顶大面板框（与 NotchGeometry.centeredTopFrame 同构）。
        let screenMaxY: CGFloat = 1000
        let panelFrame = CGRect(
            x: notchFrame.midX - resolved.width / 2,
            y: screenMaxY - resolved.height,
            width: resolved.width,
            height: resolved.height
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.retentionContainsMidLowerPoint(
                notchFrame: notchFrame,
                panelFrame: panelFrame,
                expanded: true
            ),
            "抬高后的保展开框中下点必须命中"
        )
    }

    /// 已有稳定大面板后 Preference 误报矮框：保展开仍用大面板，中下点命中。
    func test_islandHoverRetention_stablePanelWinsOverShortPreferenceReport() {
        let notchSize = CGSize(width: 179, height: 32)
        let notchFrame = CGRect(x: 400, y: 968, width: notchSize.width, height: notchSize.height)
        let stable = CGSize(width: 660, height: 300)
        let poisoned = CGSize(width: 458, height: 80)

        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldPreferStableRetention(
                panel: poisoned,
                stable: stable,
                notch: notchSize,
                isExpanded: true
            )
        )
        let resolved = IslandExpandedPanelPolicy.resolvedRetentionPanelSize(
            panel: poisoned,
            stable: stable,
            notch: notchSize,
            isExpanded: true
        )
        XCTAssertEqual(resolved.width, stable.width, accuracy: 0.5)
        XCTAssertEqual(resolved.height, stable.height, accuracy: 0.5)

        let screenMaxY: CGFloat = 1000
        let panelFrame = CGRect(
            x: notchFrame.midX - resolved.width / 2,
            y: screenMaxY - resolved.height,
            width: resolved.width,
            height: resolved.height
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.retentionContainsMidLowerPoint(
                notchFrame: notchFrame,
                panelFrame: panelFrame,
                expanded: true
            )
        )
    }

    /// ViewModel 状态机：展开后 Preference 仍报刘海 → retentionPanelSize 不得停在刘海高。
    @MainActor
    func test_islandHoverRetention_viewModelRetentionFloorsWhilePreferencePending() {
        let vm = IslandViewModel()
        vm.notchWidth = 179
        vm.notchHeight = 32
        vm.maxExpandedWidth = 2000
        vm.panelSize = CGSize(width: 179, height: 32)

        vm.expand()
        XCTAssertTrue(vm.isExpanded)

        // 模拟 Preference 尚未抬高：仍接近刘海。
        let retention = vm.retentionPanelSize(notchWidth: 179, notchHeight: 32)
        XCTAssertGreaterThan(
            retention.height,
            32 + 80,
            "展开后 Preference 未到时保展开高不得停在刘海"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: retention,
                notch: CGSize(width: 179, height: 32),
                isExpanded: true
            ),
            "retention 尺寸不得再被判定为展开态异常矮框"
        )
    }

    /// ViewModel：写入大面板后再误报矮框，retention 仍用稳定大尺寸。
    @MainActor
    func test_islandHoverRetention_viewModelKeepsStableAfterPoisonedShrink() {
        let vm = IslandViewModel()
        vm.notchWidth = 179
        vm.notchHeight = 32
        vm.maxExpandedWidth = 2000
        vm.expand()
        vm.applyMeasuredPanelSize(CGSize(width: 660, height: 300))
        XCTAssertEqual(vm.panelSize.height, 300, accuracy: 0.5)

        // 关闭缩小窗口后 Preference 误报矮框须被拒绝或 retention 仍用稳定值。
        vm.allowPanelShrink(for: -1, reason: "testCloseShrinkWindow")
        vm.applyMeasuredPanelSize(CGSize(width: 179, height: 32))
        // 误缩应被拒绝，panel 仍 300；即便写入成功 retention 也须稳定。
        let retention = vm.retentionPanelSize(notchWidth: 179, notchHeight: 32)
        XCTAssertGreaterThanOrEqual(retention.height, 200)
        XCTAssertGreaterThanOrEqual(vm.panelSize.height, 200)
    }

    /// 收起态普通移入：仅刘海可悬停展开；播放/番茄翼与控制台下方大区不算。
    func test_islandHoverExpand_collapsedOnlyNotchCountsWithoutFileDrag() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let compact = CGRect(x: 311, y: 968, width: 380, height: 32)
        let frame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: compact,
            expanded: false
        )
        let leftWing = CGPoint(x: compact.minX + 12, y: compact.midY)
        let belowNotch = CGPoint(x: notch.midX, y: notch.minY - 40)
        let inNotch = CGPoint(x: notch.midX, y: notch.midY)

        XCTAssertFalse(frame.contains(leftWing), "非拖文件时翼外不得悬停展开")
        XCTAssertFalse(frame.contains(belowNotch), "非拖文件时刘海下方大区不得识别")
        XCTAssertTrue(frame.contains(inNotch), "移入刘海须识别")

        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: belowNotch,
                notchFrame: notch,
                isFileDrag: false,
                fileDragApproachContainsMouse: true
            ),
            "即使落在接近区，非拖文件也不得展开"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: inNotch,
                notchFrame: notch,
                isFileDrag: false,
                fileDragApproachContainsMouse: false
            )
        )
    }

    /// 拖文件：宽≈刘海、高≥3 倍刘海；不得用整块控制台；普通移入仍只用刘海。
    func test_islandHoverExpand_fileDragApproachZoneOnlyWhenDraggingFiles() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let approach = IslandExpandedPanelPolicy.fileDragApproachFrame(notchFrame: notch)
        let bottomExtra = IslandExpandedPanelPolicy.fileDragApproachBottomOutset(
            notchHeight: notch.height
        )
        let midApproach = CGPoint(x: notch.midX, y: notch.minY - bottomExtra / 2)
        let nearBottomOfApproach = CGPoint(x: notch.midX, y: approach.minY + 4)
        let farBelow = CGPoint(x: notch.midX, y: approach.minY - 40)
        let farSide = CGPoint(x: notch.minX - 40, y: notch.midY)

        XCTAssertEqual(approach.width, notch.width, accuracy: 0.5, "拖文件接近区宽度须跟刘海")
        XCTAssertEqual(
            approach.height,
            notch.height * IslandExpandedPanelPolicy.fileDragApproachMinHeightInNotches,
            accuracy: 0.5,
            "拖文件接近区高度须至少 3 个刘海高"
        )
        XCTAssertGreaterThanOrEqual(
            IslandExpandedPanelPolicy.fileDragApproachMinHeightInNotches,
            3,
            "高度倍数不得再压回低于 3"
        )
        XCTAssertTrue(approach.contains(midApproach), "拖文件须能从刘海下方吸住")
        XCTAssertTrue(approach.contains(nearBottomOfApproach), "接近区底部内侧须可命中")
        XCTAssertFalse(approach.contains(farBelow), "接近区不得再向下无限延伸")
        XCTAssertFalse(approach.contains(farSide), "接近区左右不得宽于刘海")
        XCTAssertFalse(
            IslandExpandedPanelPolicy.hoverExpandFrame(notchFrame: notch).contains(midApproach),
            "普通刘海热区不含下方外扩带"
        )

        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: midApproach,
                notchFrame: notch,
                isFileDrag: true,
                fileDragApproachContainsMouse: approach.contains(midApproach)
            ),
            "拖文件时接近区可展开"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: midApproach,
                notchFrame: notch,
                isFileDrag: false,
                fileDragApproachContainsMouse: approach.contains(midApproach)
            ),
            "非拖文件时接近区不可展开"
        )
    }

    /// 展开大岛保展开不得被拖文件接近区（仅 3×刘海高）截短——下半截必须仍命中。
    func test_islandHoverRetention_expandedStayOpenNotClippedByFileDragApproach() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let screenMaxY: CGFloat = 1000
        let panel = CGRect(x: 170, y: screenMaxY - 300, width: 660, height: 300)
        let approach = IslandExpandedPanelPolicy.fileDragApproachFrame(notchFrame: notch)
        let midLower = CGPoint(x: panel.midX, y: panel.minY + panel.height * 0.25)

        XCTAssertFalse(
            approach.contains(midLower),
            "大岛下半截本就在拖文件接近区外——接近区不可代替展开保展开"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.retentionContainsMidLowerPoint(
                notchFrame: notch,
                panelFrame: panel,
                expanded: true
            ),
            "展开态大岛下半截必须仍在保展开区"
        )
        let expandedFrame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: true
        )
        XCTAssertTrue(expandedFrame.contains(midLower))
        // 收起态不得用大面板（普通移入只认刘海）。
        let collapsedFrame = IslandExpandedPanelPolicy.retentionFrame(
            notchFrame: notch,
            panelFrame: panel,
            expanded: false
        )
        XCTAssertFalse(
            collapsedFrame.contains(midLower),
            "收起态不得把大岛框当成悬停展开区"
        )
    }

    /// 未入舱松手：仅离开大岛才强收；仍在大岛下半截松手不得收；冷却内普通悬停不得再开。
    func test_shelfFileDragCancel_forceCollapseAndSuppressHoverReopen() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let inNotch = CGPoint(x: notch.midX, y: notch.midY)
        let approach = IslandExpandedPanelPolicy.fileDragApproachFrame(notchFrame: notch)
        let inApproach = CGPoint(
            x: notch.midX,
            y: notch.minY - IslandExpandedPanelPolicy.fileDragApproachBottomOutset(
                notchHeight: notch.height
            ) / 2
        )

        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceCollapseAfterShelfFileDragMouseUp(
                hadShelfFileDragExpand: true,
                dropCompletedRecently: false,
                isExpanded: true,
                pointerInExpandedRetention: false
            ),
            "已离开展开大岛 → 强收"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceCollapseAfterShelfFileDragMouseUp(
                hadShelfFileDragExpand: true,
                dropCompletedRecently: false,
                isExpanded: true,
                pointerInExpandedRetention: true
            ),
            "仍在大岛保展开区内松手不得强收（防移到一半就收）"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceCollapseAfterShelfFileDragMouseUp(
                hadShelfFileDragExpand: true,
                dropCompletedRecently: true,
                isExpanded: true,
                pointerInExpandedRetention: false
            ),
            "刚成功入舱不得当取消强收"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceCollapseAfterShelfFileDragMouseUp(
                hadShelfFileDragExpand: false,
                dropCompletedRecently: false,
                isExpanded: true,
                pointerInExpandedRetention: false
            ),
            "非货架拖文件展开不得误强收"
        )

        // 冷却内：刘海内普通移入也不得展开（回头再开）。
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: inNotch,
                notchFrame: notch,
                isFileDrag: false,
                fileDragApproachContainsMouse: false,
                hoverExpandSuppressed: true
            ),
            "松手冷却内禁止普通悬停展开"
        )
        // 冷却不影响下一次真正拖文件。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: inApproach,
                notchFrame: notch,
                isFileDrag: true,
                fileDragApproachContainsMouse: approach.contains(inApproach),
                hoverExpandSuppressed: true
            ),
            "冷却中仍允许拖文件接近区展开"
        )
        // 冷却结束后刘海移入恢复。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForPointer(
                mouse: inNotch,
                notchFrame: notch,
                isFileDrag: false,
                fileDragApproachContainsMouse: false,
                hoverExpandSuppressed: false
            )
        )
        XCTAssertGreaterThan(IslandExpandedPanelPolicy.postFileDragHoverSuppress, 0.3)
    }

    @MainActor
    func test_shelfFileDragCancel_sessionSuppressBlocksStagingReactivate() {
        let session = ShelfDropSession.shared
        session.resetForTests()
        defer { session.resetForTests() }

        session.setActive(true, reason: "testApproach")
        XCTAssertTrue(session.isActive)
        // 未入舱取消：不开 markCompleted。
        session.endAfterDrop(reason: "fileDragCanceled", markCompleted: false)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.dropCompletedRecently())
        session.setActive(true, reason: "approach")
        XCTAssertFalse(session.isActive, "取消后冷却内不得再进双舱")
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

    /// 展开动画默认须为「标准」档，与分段控件一致。
    func test_islandAnimationSpeed_defaultsToStandardPreset() {
        XCTAssertEqual(
            IslandSettings.Defaults.animationSpeed,
            IslandAnimationSpeedPreset.standard.rawValue,
            accuracy: 0.001
        )
        XCTAssertEqual(IslandAnimationSpeedPreset.standard.rawValue, 1.5, accuracy: 0.001)
        XCTAssertEqual(IslandAnimationSpeedPreset.smooth.rawValue, 0.8, accuracy: 0.001)
        XCTAssertEqual(IslandAnimationSpeedPreset.snap.rawValue, 2.0, accuracy: 0.001)
    }

    /// 磁吸拖放默认开；关闭后恢复默认须回到开（双舱 / 接近区仅开时启用）。
    /// 磁吸开关不改变拖文件接近区；只改变是否进双舱。
    func test_shelfMagneticDrop_approachZoneIndependentOfToggle() {
        let notch = CGRect(x: 411, y: 968, width: 180, height: 32)
        let approach = IslandExpandedPanelPolicy.fileDragApproachFrame(notchFrame: notch)
        XCTAssertEqual(approach.width, notch.width, accuracy: 0.5)
        XCTAssertEqual(
            approach.height,
            notch.height * IslandExpandedPanelPolicy.fileDragApproachMinHeightInNotches,
            accuracy: 0.5
        )

        XCTAssertTrue(
            IslandExpandedPanelPolicy.isFileDragApproachEnabled(shelfEnabled: true, isFileDrag: true)
        )
        // 磁吸关：接近区仍启用。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isFileDragApproachEnabled(shelfEnabled: true, isFileDrag: true),
            "磁吸关也须保留拖文件接近区"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isMagneticStagingEnabled(
                shelfEnabled: true,
                magneticEnabled: false,
                isFileDrag: true
            ),
            "磁吸关不得进双舱"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isMagneticStagingEnabled(
                shelfEnabled: true,
                magneticEnabled: true,
                isFileDrag: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isFileDragApproachEnabled(shelfEnabled: true, isFileDrag: false)
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isFileDragApproachEnabled(shelfEnabled: false, isFileDrag: true)
        )
    }

    @MainActor
    func test_shelfMagneticDropCapture_defaultsOnAndRestore() {
        XCTAssertTrue(
            ShelfSettings.magneticDropCaptureDefaultEnabled,
            "磁吸拖放产品默认必须为开"
        )
        let settings = ShelfSettings.shared
        let previous = settings.magneticDropCaptureEnabled
        defer {
            settings.magneticDropCaptureEnabled = previous
            ShelfDropSession.shared.resetForTests()
        }

        settings.magneticDropCaptureEnabled = false
        XCTAssertFalse(settings.magneticDropCaptureEnabled)
        XCTAssertFalse(ShelfDropSession.shared.isActive)

        settings.restoreMagneticDropDefaults()
        XCTAssertTrue(settings.magneticDropCaptureEnabled)
        XCTAssertEqual(
            settings.magneticDropCaptureEnabled,
            ShelfSettings.magneticDropCaptureDefaultEnabled
        )
    }

    /// 投放完成后 isTargeted 滞后不得再点亮双舱（「用完又冒一次」）。
    @MainActor
    func test_shelfMagneticStagingDouble_postDropSuppressBlocksReactivate() {
        let session = ShelfDropSession.shared
        session.resetForTests()
        defer { session.resetForTests() }

        session.setActive(true, reason: "testApproach")
        XCTAssertTrue(session.isActive)

        session.endAfterDrop(reason: "dropComplete")
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.isReactivateSuppressed)
        XCTAssertGreaterThan(ShelfDropSession.postDropSuppress, 0.3)

        // 模拟松手后 SwiftUI isTargeted / 轮询再次请求进入。
        session.setActive(true, reason: "dropTargeted")
        XCTAssertFalse(session.isActive, "冷却期内不得再次进入双舱")
        session.setActive(true, reason: "approach")
        XCTAssertFalse(session.isActive)
    }

    /// 取色 / 框选翼引导 →「已复制」圆岛：缩宽必须可应用，否则卡在翼尺寸看不见提示。
    func test_shelfCopiedNoticeMiss_wingGuideToCopiedAllowsWidthShrink() {
        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: notchW, notchHeight: notchH)
        let orb = IslandChrome.preparedNotchRightOrbPanelSize()

        XCTAssertTrue(IslandNoticePayload.colorPickTip.usesNotchWingChrome)
        XCTAssertTrue(IslandNoticePayload.ocrSelectTip.usesNotchWingChrome)
        let copied = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.color.test",
            text: "已复制",
            symbol: "eyedropper"
        )
        XCTAssertTrue(copied.usesNotchRightOrbChrome)
        XCTAssertFalse(copied.usesShortBelowNotchChrome)
        XCTAssertFalse(copied.usesNotchWingChrome)
        // Cmd+C 后指针常不在岛上：须保持展开至自动收起，否则展开中途就被 hoverEnd 收掉。
        XCTAssertTrue(copied.keepsExpandedWithoutHover)
        // 「已复制」= 入场 + 定格（约 1.4s），不悬停续命。
        XCTAssertEqual(
            copied.autoDismissNanoseconds,
            IslandChrome.notchRightOrbAutoDismissNanoseconds
        )
        XCTAssertEqual(IslandChrome.notchRightOrbEntranceNanoseconds, 900_000_000)
        XCTAssertEqual(IslandChrome.notchRightOrbLingerNanoseconds, 500_000_000)
        XCTAssertFalse(copied.holdsWhileHovering)

        XCTAssertEqual(orb.width, IslandChrome.notchRightOrbDiameter)
        XCTAssertEqual(orb.height, IslandChrome.notchRightOrbDiameter)
        XCTAssertGreaterThan(
            IslandChrome.notchRightOrbCenterOffsetX(notchWidth: notchW),
            notchW / 2,
            "圆岛中心须在刘海右缘之外"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldApplyMeasuredSize(
                current: wing,
                measured: orb,
                isExpanded: true,
                allowShrink: false
            ),
            "翼→已复制圆岛：无 allowShrink 窗口也须放行（shelf-copied-notice-miss）"
        )
    }

    func test_shelfCopiedNoticeMiss_preparedOrbSizeAndClamp() {
        // 预备尺寸契约：present(copy) 先 force 到 Ø32，且 clamp 不得抬到刘海宽。
        let orb = IslandChrome.preparedNotchRightOrbPanelSize()
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: 160, notchHeight: 32)
        XCTAssertTrue(IslandChrome.isNotchRightOrbPanelSize(orb))
        XCTAssertLessThan(orb.width, wing.width)
        XCTAssertEqual(IslandChrome.notchRightOrbGap, 2)
        XCTAssertEqual(IslandChrome.preparedWingWidth, 98)
        XCTAssertEqual(IslandChrome.preparedPeripheralWingWidth, 78)
        XCTAssertLessThan(
            IslandChrome.preparedPeripheralWingWidth,
            IslandChrome.preparedWingWidth,
            "外设满岛翼宽须窄于会议翼，长设备名靠滚动"
        )
        let meetingWing = IslandChrome.preparedWingTipPanelSize(notchWidth: 160, notchHeight: 32)
        let peripheralWing = IslandChrome.preparedWingTipPanelSize(
            notchWidth: 160,
            notchHeight: 32,
            wingWidth: IslandChrome.preparedPeripheralWingWidth
        )
        XCTAssertLessThan(peripheralWing.width, meetingWing.width)
        let clamped = IslandPanelSizing.clamp(
            orb,
            notchWidth: 160,
            notchHeight: 32,
            maxWidth: 2000
        )
        XCTAssertEqual(clamped.width, IslandChrome.notchRightOrbDiameter)
        XCTAssertEqual(clamped.height, IslandChrome.notchRightOrbDiameter)
    }

    /// 半块 flush 档位映射；满岛会议入会钮色/文案保持原契约（勿被 flush 稿改掉）。
    func test_islandFlushWing_severityColorsAndMeetingJoinLabel() {
        XCTAssertEqual(L10n.Meeting.joinEnter, "入会")
        // 半块会议固定日程 calendar；勿用 video.fill。
        XCTAssertEqual(MeetingLeadUrgency.relaxed.flushSymbolName, "calendar")
        XCTAssertEqual(MeetingLeadUrgency.warning.flushSymbolName, "calendar")
        XCTAssertEqual(MeetingLeadUrgency.critical.flushSymbolName, "calendar")
        XCTAssertEqual(MeetingLeadUrgency.relaxed.symbolName, "calendar")
        XCTAssertEqual(MeetingLeadUrgency.warning.symbolName, "video.fill")
        XCTAssertEqual(MeetingLeadUrgency.relaxed.flushSeverity, .info)
        XCTAssertEqual(MeetingLeadUrgency.warning.flushSeverity, .warning)
        XCTAssertEqual(MeetingLeadUrgency.critical.flushSeverity, .danger)
        // 半岛充裕须蓝（info），不得跟满岛绿。
        XCTAssertEqual(
            MeetingLeadUrgency.relaxed.flushAccent,
            IslandFlushWingStyle.Severity.info.accent
        )
        XCTAssertNotEqual(
            MeetingLeadUrgency.relaxed.flushAccent,
            MeetingLeadUrgency.relaxed.accent
        )
        XCTAssertEqual(AIUsageStage.abundant.flushSeverity, .info)
        XCTAssertEqual(AIUsageStage.warning.flushSeverity, .warning)
        XCTAssertEqual(AIUsageStage.critical.flushSeverity, .danger)
        // 满岛入会钮：充裕白底黑字，勿变成 flush morph 蓝底白字。
        XCTAssertEqual(MeetingLeadUrgency.relaxed.joinForeground, .black)
        XCTAssertEqual(MeetingLeadUrgency.relaxed.joinBackground, .white)
        XCTAssertEqual(IslandFlushWingStyle.width, 112)
        XCTAssertEqual(IslandFlushWingStyle.height, 34)
        XCTAssertEqual(IslandFlushWingStyle.outerBottomRadius, 14)
        XCTAssertEqual(
            MeetingLeadUrgency.resolve(secondsToStart: 6 * 60),
            .relaxed
        )
        XCTAssertEqual(
            MeetingLeadUrgency.resolve(secondsToStart: 3 * 60),
            .warning
        )
        XCTAssertEqual(
            MeetingLeadUrgency.resolve(secondsToStart: 60),
            .critical
        )
    }

    /// 会议等无自动收的 sticky：设置设计页 / 指针在设置窗禁止强制展开（防连震）。
    /// 约 3s 瞬时 tip：设置开着也要强制展开，与悬停无关。
    func test_shelfCopiedNoticeMiss_settingsBlocksStickyForceExpand() {
        // 挡 tip 须「收起会话 + 设计 sticky」；其余设置页走正式程序 expand。
        XCTAssertFalse(
            IslandExpandedPanelPolicy.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: false
            )
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: false,
                designSticky: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.settingsBlocksProgrammaticNoticeExpand(
                sessionActive: true,
                livePreview: true,
                designSticky: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: true,
                pointerOverSettings: false
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: true
            )
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: false
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: true,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: false,
                pointerOverSettings: false
            )
        )
        // 瞬时 tip：设置会话 / 指针在设置窗也强制展开。
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldForceStickyNoticeExpand(
                isExpanded: false,
                keepsExpandedWithoutHover: true,
                settingsSessionBlocksIslandTips: true,
                pointerOverSettings: true,
                expandsDuringSettingsSession: true
            )
        )
        let ram = IslandNoticePayload.ramPressure(
            .init(
                id: "resource.ram.settings-expand",
                ramUsedBytes: 28 * 1024 * 1024 * 1024,
                ramPercent: 96,
                topAppName: "Google Chrome",
                topAppBundleID: "com.google.Chrome",
                topAppMemoryBytes: 4_200 * 1024 * 1024
            )
        )
        XCTAssertTrue(ram.expandsDuringSettingsSession)
        XCTAssertTrue(ram.keepsExpandedWithoutHover)
        XCTAssertEqual(ram.autoDismissNanoseconds, 3_000_000_000)
        // Ø32 圆岛不得被当成「展开态缩回刘海」异常。
        let orb = IslandChrome.preparedNotchRightOrbPanelSize()
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isCollapsedSizedWhileExpanded(
                panel: orb,
                notch: CGSize(width: 172, height: 32),
                isExpanded: true
            )
        )
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
        XCTAssertEqual(IslandChrome.contentHorizontal, 7)
        XCTAssertEqual(IslandChrome.contentBottom, 7)
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
        let orb = IslandChrome.insets(for: .notchRightOrb, notchHeight: notchH)
        let dualFlush = IslandChrome.insets(for: .dualFlush, notchHeight: notchH)

        // 展开 / 翼 / 短 tip / 普通通知：左右边距同一固定令牌。
        for insets in [expanded, wing, shortTip, notice] {
            XCTAssertEqual(insets.horizontal, IslandChrome.contentHorizontal)
        }
        // 双槽贴刘海 / 圆岛：零 inset，勿叠 tip 边距把内容挤没。
        XCTAssertEqual(dualFlush.top, 0)
        XCTAssertEqual(dualFlush.bottom, 0)
        XCTAssertEqual(dualFlush.horizontal, 0)

        XCTAssertEqual(expanded.bottom, IslandChrome.contentBottom)
        XCTAssertEqual(notice.bottom, IslandChrome.contentBottom)
        // 翼 tip / 短 tip 底距必须用紧凑令牌，禁止误退回 contentBottom（会议 tip 曾叠大底距）。
        XCTAssertEqual(wing.bottom, IslandChrome.compactTipBottom)
        XCTAssertEqual(wing.top, IslandChrome.compactTipTopInset)
        XCTAssertEqual(shortTip.bottom, IslandChrome.shortTipBottom)
        XCTAssertNotEqual(wing.bottom, IslandChrome.contentBottom)
        XCTAssertNotEqual(shortTip.bottom, IslandChrome.contentBottom)
        // 「已复制」圆岛：内容自撑 Ø32，壳层零 inset。
        XCTAssertEqual(orb.top, 0)
        XCTAssertEqual(orb.bottom, 0)
        XCTAssertEqual(orb.horizontal, 0)
    }

    /// 满岛翼 tip 内容翼宽必须 == 壳层预备翼宽。
    /// 网络 tip 曾硬编码 104、壳层按 98 预备 → 裁切/空边（2026-11-23）。
    func test_islandChromeDoublePadding_wingTipCardsMatchPreparedWingWidth() {
        let meetingWing = IslandChrome.preparedWingWidth
        let networkWing = IslandChrome.preparedNetworkLinkWingWidth
        XCTAssertEqual(meetingWing, 98)
        XCTAssertEqual(networkWing, 84)
        XCTAssertLessThan(networkWing, meetingWing)
        XCTAssertEqual(NetworkLinkNoticeCard.liveWingWidth, networkWing)
        XCTAssertEqual(MacBatteryNoticeCard.liveWingWidth, meetingWing)
        XCTAssertEqual(MeetingIslandCardView.liveWingWidth, meetingWing)
        XCTAssertEqual(
            PeripheralBatteryNoticeCard.liveWingWidth,
            IslandChrome.preparedPeripheralWingWidth
        )

        let notchW: CGFloat = 179
        let notchH: CGFloat = 32
        let contentW = networkWing * 2 + notchW
        let prepared = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW,
            notchHeight: notchH,
            wingWidth: networkWing
        )
        XCTAssertEqual(
            prepared.width,
            contentW + IslandChrome.horizontalInsetTotal,
            accuracy: 0.5,
            "预备面板宽 = 内容(翼×2+刘海) + chrome；卡内翼宽不得另写魔数"
        )

        let net = IslandNoticePayload.networkWifiConnected(
            .init(id: "n", kind: .wifiConnected, title: "Wi‑Fi")
        )
        XCTAssertFalse(net.usesCompactPeripheralWing)
        XCTAssertTrue(net.usesNetworkLinkWing)
        XCTAssertTrue(net.usesNotchWingChrome)
    }

    /// 外设满岛翼 tip：外缘只计壳层 horizontal 一次；预备宽 = 内容宽 + horizontalInsetTotal。
    /// 卡根再叠 bareContentLeading / trailing = 左右空档过大；
    /// 右翼不占满 wingWidth 时 HStack+.frame 居中，左右外缘再空一截（2026-11-23）。
    func test_islandChromeDoublePadding_peripheralWingTipOuterInsetIsChromeOnly() {
        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let wingInsets = IslandChrome.insets(for: .notchWingTip, notchHeight: notchH)
        XCTAssertEqual(wingInsets.horizontal, IslandChrome.contentHorizontal)

        let wingW = IslandChrome.preparedPeripheralWingWidth
        // 左右各占满一翼：子宽必须等于 totalWidth，禁止右翼 fixedSize 欠宽导致居中空边。
        let contentW = wingW + max(notchW, 110) + wingW
        XCTAssertEqual(contentW, wingW * 2 + max(notchW, 110), accuracy: 0.5)
        let prepared = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW,
            notchHeight: notchH,
            wingWidth: wingW
        )
        XCTAssertEqual(
            prepared.width,
            contentW + IslandChrome.horizontalInsetTotal,
            accuracy: 0.5,
            "预备面板已含左右 chrome；卡内禁止再叠外缘 padding"
        )
        // bareContentLeading 只给 dualFlush bare，不得当成满岛翼 tip 外缘。
        XCTAssertEqual(IslandFlushWingStyle.bareContentLeading, 10)
        XCTAssertGreaterThan(
            IslandChrome.contentHorizontal + IslandFlushWingStyle.bareContentLeading,
            IslandChrome.contentHorizontal,
            "叠两层会大于壳层令牌——测试锁定「禁止叠」契约"
        )

        let peripheral = IslandNoticePayload.peripheralConnected(
            BatteryPeripheralNotice(
                id: "pad.test",
                deviceID: "d",
                deviceName: "Mouse",
                kind: .mouse,
                percent: 51,
                threshold: 0,
                detail: "c"
            )
        )
        XCTAssertTrue(peripheral.usesNotchWingChrome)
        XCTAssertTrue(peripheral.usesCompactPeripheralWing)
    }

    func test_islandChrome_meetingUsesNotchWing_copiedUsesRightOrb() {
        // 会议 / AI / 久坐 / 取色 / 框选：左右翼贴刘海；「已复制」为刘海右侧圆岛。
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
        XCTAssertFalse(copied.usesShortBelowNotchChrome)
        XCTAssertTrue(copied.usesNotchRightOrbChrome)
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

    /// meeting-join-wrong-calendar-url：EventKit 日程页不得盖住备注里的真入会链。
    func test_meetingJoinLink_prefersConferenceURLOverCalendarEventPage() {
        let calendarPage = URL(string: "https://www.google.com/calendar/event?eid=abc123")!
        let zoom = URL(string: "https://zoom.us/j/123456789?pwd=secret")!
        XCTAssertTrue(MeetingLinkDetector.isLikelyCalendarEventPage(calendarPage))
        XCTAssertFalse(MeetingLinkDetector.isLikelyCalendarEventPage(zoom))

        let target = MeetingLinkDetector.detect(
            location: nil,
            notes: "Join Zoom: \(zoom.absoluteString)",
            url: calendarPage
        )
        XCTAssertEqual(target?.platform, .zoom)
        XCTAssertEqual(target?.sourceURL.host, "zoom.us")
        XCTAssertEqual(target?.openURL.scheme, "zoommtg")
        XCTAssertTrue(target?.openURL.absoluteString.contains("confno=123456789") == true)

        // 仅日程页、无会议链 → 不入会（禁止打开 Google 日历页冒充 Join）。
        XCTAssertNil(
            MeetingLinkDetector.detect(location: nil, notes: nil, url: calendarPage)
        )

        // 钉钉：保留原 https，勿换成无会议号的通用 conference 深链。
        let ding = URL(string: "https://meeting.dingtalk.com/j/abcdef")!
        let dingTarget = MeetingLinkDetector.detect(location: nil, notes: nil, url: ding)
        XCTAssertEqual(dingTarget?.platform, .dingTalk)
        XCTAssertEqual(dingTarget?.openURL, ding)
    }

    /// meeting-join-wrong-calendar-url：Outlook / iCloud 日程页也须识别并跳过。
    func test_meetingJoinLink_skipsOutlookAndICloudCalendarPages() {
        let outlook = URL(string: "https://outlook.office.com/calendar/item/AAMkAGI")!
        let outlook365 = URL(string: "https://outlook.office365.com/owa/?itemid=abc")!
        let live = URL(string: "https://outlook.live.com/calendar/0/deeplink/compose")!
        let icloud = URL(string: "https://www.icloud.com/calendar/event/abc")!
        let googleHost = URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit/abc")!

        for page in [outlook, outlook365, live, icloud, googleHost] {
            XCTAssertTrue(
                MeetingLinkDetector.isLikelyCalendarEventPage(page),
                "须识别为日程页: \(page.host ?? "")"
            )
            XCTAssertNil(
                MeetingLinkDetector.detect(location: nil, notes: nil, url: page),
                "仅日程页不得冒充入会: \(page.host ?? "")"
            )
        }

        let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
        let fromOutlook = MeetingLinkDetector.detect(
            location: meet.absoluteString,
            notes: nil,
            url: outlook
        )
        XCTAssertEqual(fromOutlook?.platform, .googleMeet)
        XCTAssertEqual(fromOutlook?.openURL, meet)
    }

    /// meeting-join-wrong-calendar-url：location 里的腾讯会优先于 EventKit 日程 url。
    func test_meetingJoinLink_locationTencentBeatsCalendarURL() {
        let calendarPage = URL(string: "https://www.google.com/calendar/event?eid=xyz")!
        let tencent = URL(string: "https://meeting.tencent.com/dm/AbCdEfGh?meeting_code=123456789")!
        let target = MeetingLinkDetector.detect(
            location: "腾讯会议 \(tencent.absoluteString)",
            notes: nil,
            url: calendarPage
        )
        XCTAssertEqual(target?.platform, .tencentMeeting)
        XCTAssertEqual(target?.sourceURL.host, "meeting.tencent.com")
        XCTAssertNotEqual(target?.openURL.host, "www.google.com")
        XCTAssertFalse(
            MeetingLinkDetector.isLikelyCalendarEventPage(target!.openURL),
            "入会 openURL 不得仍是日程页"
        )
    }

    /// meeting-join-wrong-calendar-url：notes 泛型 https 可用；EventKit url 泛型日程页不可。
    func test_meetingJoinLink_genericOnlyFromTextNotCalendarURL() {
        let calendarPage = URL(string: "https://www.google.com/calendar/event?eid=only")!
        let genericJoin = URL(string: "https://example.com/room/42")!

        XCTAssertNil(
            MeetingLinkDetector.detect(location: nil, notes: nil, url: calendarPage),
            "日程页不得当 generic 入会"
        )

        let fromNotes = MeetingLinkDetector.detect(
            location: nil,
            notes: "网页会：\(genericJoin.absoluteString)",
            url: calendarPage
        )
        XCTAssertEqual(fromNotes?.platform, .generic)
        XCTAssertEqual(fromNotes?.openURL, genericJoin)

        // 已知平台须压过同场 notes 里的泛型链接。
        let zoom = URL(string: "https://zoom.us/j/999888777")!
        let preferKnown = MeetingLinkDetector.detect(
            location: nil,
            notes: "\(genericJoin.absoluteString)\n\(zoom.absoluteString)",
            url: calendarPage
        )
        XCTAssertEqual(preferKnown?.platform, .zoom)
    }

    /// meeting-join-wrong-calendar-url：会话入会须打开 detector 解析出的链，而非日程页。
    @MainActor
    func test_meetingJoinLink_sessionOpensDetectorURLNotCalendarPage() {
        let session = MeetingLeadSession.shared
        session.resetForTests()
        IslandNoticeCenter.shared.dismiss(id: nil)
        defer {
            session.resetForTests()
            IslandNoticeCenter.shared.dismiss(id: nil)
        }

        let calendarPage = URL(string: "https://www.google.com/calendar/event?eid=session")!
        let zoomWeb = URL(string: "https://zoom.us/j/555666777?pwd=p")!
        let detected = MeetingLinkDetector.detect(
            location: nil,
            notes: zoomWeb.absoluteString,
            url: calendarPage
        )
        XCTAssertEqual(detected?.platform, .zoom)
        guard let join = detected else {
            XCTFail("须解析出 Zoom")
            return
        }

        var opened: [URL] = []
        session.openURLHandler = { url in
            opened.append(url)
            return true
        }

        let now = Date()
        session.publish(
            .init(
                meetingID: "m-join-url",
                title: "入会链验收",
                startDate: now.addingTimeInterval(5 * 60),
                endDate: now.addingTimeInterval(35 * 60),
                secondsToStart: 5 * 60,
                showJoin: true,
                showAuth: false,
                joinOpenURL: join.openURL,
                joinSourceURL: join.sourceURL,
                joinPlatform: join.logLabel
            ),
            reason: "testJoinURL"
        )
        session.joinFromNotice()

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.scheme, "zoommtg")
        XCTAssertTrue(opened.first?.absoluteString.contains("confno=555666777") == true)
        XCTAssertFalse(opened.contains(calendarPage), "禁止打开 Google 日程页")
    }

    /// island-focus-steal：久坐常驻 tip 须 keepExpanded；可点区不得窄于预备双翼宽。
    func test_islandFocusSteal_moveReminderWingTipInteractiveFloor() {
        let move = IslandNoticePayload.moveReminder(
            .init(id: "move.focus", activeMinutes: 30, restMinutes: 2)
        )
        XCTAssertTrue(move.keepsExpandedWithoutHover)
        XCTAssertTrue(move.usesNotchWingChrome)
        XCTAssertEqual(move.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertEqual(move.preemptionRank, 50)

        let notchW: CGFloat = 179
        let notchH: CGFloat = 32
        let prepared = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW,
            notchHeight: notchH
        )
        // 误缩成刘海宽时，可点区仍须抬回双翼预备宽（否则右翼 +10m 点穿）。
        let floored = IslandExpandedPanelPolicy.wingTipInteractivePanelSize(
            current: CGSize(width: notchW - 7, height: notchH),
            notchWidth: notchW,
            notchHeight: notchH,
            usesNotchWingChrome: true
        )
        XCTAssertEqual(floored.width, prepared.width, accuracy: 0.5)
        XCTAssertEqual(floored.height, prepared.height, accuracy: 0.5)
        XCTAssertGreaterThan(floored.width, notchW + 100)

        let untouched = IslandExpandedPanelPolicy.wingTipInteractivePanelSize(
            current: CGSize(width: 200, height: 40),
            notchWidth: notchW,
            notchHeight: notchH,
            usesNotchWingChrome: false
        )
        XCTAssertEqual(untouched.width, 200, accuracy: 0.5)
    }

    /// focus-completed-clipped-by-notch：终局须翼 tip（顶 0），高度远小于展开页，消灭大顶空。
    func test_focusCompletedClippedByNotch_topInsetClearsNotch() {
        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let wingInsets = IslandChrome.insets(for: .notchWingTip, notchHeight: notchH)
        XCTAssertEqual(wingInsets.top, 0, accuracy: 0.5, "终局壳层须 notchWingTip 顶距 0")
        XCTAssertEqual(wingInsets.bottom, IslandChrome.compactTipBottom, accuracy: 0.5)
        XCTAssertEqual(FocusTimerContentSize.completedPreviewTopInset, 0, accuracy: 0.5)
        XCTAssertEqual(
            FocusTimerContentSize.completedBottomInset,
            IslandChrome.compactTipBottom,
            accuracy: 0.5
        )

        let completed = FocusTimerContentSize.panelSize(
            phase: .completed,
            notchHeight: notchH,
            notchWidth: notchW
        )
        let expandedPick = FocusTimerContentSize.panelSize(
            phase: .picking,
            notchHeight: notchH,
            notchWidth: notchW
        )
        let expected = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW + FocusTimerContentSize.completedCenterExtra,
            notchHeight: notchH,
            wingWidth: FocusTimerContentSize.completedWingWidth
        )
        XCTAssertEqual(completed.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(completed.height, expected.height, accuracy: 0.5)
        XCTAssertLessThan(
            completed.height,
            expandedPick.height - 20,
            "终局翼 tip 须明显矮于选时展开页，用户才能感到顶空消失"
        )
        XCTAssertEqual(FocusTimerContentSize.completedWingWidth, 120, accuracy: 0.5)
        XCTAssertEqual(FocusTimerContentSize.completedCenterExtra, 8, accuracy: 0.5)
    }

    /// peripheral-wing-floor-meeting-width：外设窄翼可点区抬升须用 peripheral 预备宽，禁止抬成会议翼（否则左右空一边）。
    func test_peripheralWingFloorMeetingWidth_interactiveUsesCompactWing() {
        let notice = BatteryPeripheralNotice(
            id: "test.peripheral.floor",
            deviceID: "d-floor",
            deviceName: "Magic Mouse",
            kind: .mouse,
            percent: 42,
            threshold: 20,
            detail: "low"
        )
        let peripheral = IslandNoticePayload.peripheralLowBattery(notice)
        XCTAssertTrue(peripheral.usesNotchWingChrome)
        XCTAssertTrue(peripheral.usesCompactPeripheralWing)

        let slots = IslandNoticeSlots(secondary: peripheral)
        XCTAssertEqual(slots.resolvedLayout, .fullNotice(peripheral))
        XCTAssertTrue(slots.anyUsesNotchWingChrome)
        XCTAssertTrue(slots.anyUsesCompactPeripheralWing)
        XCTAssertEqual(slots.wingTipPreparedWingWidth, IslandChrome.preparedPeripheralWingWidth)

        let notchW: CGFloat = 160
        let notchH: CGFloat = 32
        let peripheralPrepared = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW,
            notchHeight: notchH,
            wingWidth: IslandChrome.preparedPeripheralWingWidth
        )
        let meetingPrepared = IslandChrome.preparedWingTipPanelSize(
            notchWidth: notchW,
            notchHeight: notchH
        )
        XCTAssertLessThan(peripheralPrepared.width, meetingPrepared.width)

        // 已是外设预备宽时，地板不得再抬成会议宽。
        let floored = IslandExpandedPanelPolicy.wingTipInteractivePanelSize(
            current: peripheralPrepared,
            notchWidth: notchW,
            notchHeight: notchH,
            usesNotchWingChrome: true,
            wingWidth: slots.wingTipPreparedWingWidth
        )
        XCTAssertEqual(floored.width, peripheralPrepared.width, accuracy: 0.5)
        XCTAssertLessThan(floored.width, meetingPrepared.width)

        // 误缩时只抬回外设预备宽，仍窄于会议。
        let rescued = IslandExpandedPanelPolicy.wingTipInteractivePanelSize(
            current: CGSize(width: notchW - 7, height: notchH),
            notchWidth: notchW,
            notchHeight: notchH,
            usesNotchWingChrome: true,
            wingWidth: IslandChrome.preparedPeripheralWingWidth
        )
        XCTAssertEqual(rescued.width, peripheralPrepared.width, accuracy: 0.5)
        XCTAssertLessThan(rescued.width, meetingPrepared.width)
    }

    /// meeting-tip-preemption：会议 tip 在场时，次档不得整岛替换（改走副槽并排）。
    func test_meetingTipPreemption_blocksLowerPriorityWhileMeetingShowing() {
        let meeting = IslandNoticePayload.meetingLead(meetingID: "m1")
        let otherMeeting = IslandNoticePayload.meetingLead(meetingID: "m2")
        let copy = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.test",
            text: "已复制",
            symbol: "doc.on.doc"
        )
        let exclusive = IslandNoticePayload.colorPickTip
        let move = IslandNoticePayload.moveReminder(
            .init(id: "move.preempt", activeMinutes: 30, restMinutes: 2)
        )

        XCTAssertEqual(meeting.preemptionRank, 100)
        XCTAssertEqual(move.preemptionRank, 50)
        XCTAssertEqual(copy.preemptionRank, 0)
        XCTAssertEqual(meeting.displayLane, .primary)
        XCTAssertEqual(copy.displayLane, .secondary)
        XCTAssertEqual(exclusive.displayLane, .exclusive)
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: nil))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: copy))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: otherMeeting, replacing: meeting))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: meeting))
        // 旧单槽语义：次档不得整岛盖住主提示。
        XCTAssertFalse(IslandNoticePreemption.shouldAccept(incoming: copy, replacing: meeting))
        // 独占工具可清槽上岛。
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: exclusive, replacing: meeting))
        // 短 C 可暂占粘性 C（久坐 park，复制上右翼）。
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: copy, replacing: move))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: meeting, replacing: move))
        XCTAssertTrue(IslandNoticePreemption.shouldAccept(incoming: move, replacing: copy))
    }

    /// RAM 高压是 C：单独左右双翼贴刘海（左用量、右 Top App）；与 B 并排居右半块；常驻 tip。
    func test_islandNoticeDualSlots_ramPressureUsesDualFlushSolo() {
        let ram = IslandNoticePayload.ramPressure(
            .init(
                id: "resource.ram.test",
                ramUsedBytes: 28 * 1024 * 1024 * 1024,
                ramPercent: 96,
                topAppName: "Google Chrome",
                topAppBundleID: "com.google.Chrome",
                topAppMemoryBytes: 4_200 * 1024 * 1024
            )
        )
        XCTAssertEqual(ram.displayLane, .secondary)
        XCTAssertEqual(ram.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertTrue(ram.usesDualFlushSoloChrome)
        XCTAssertFalse(ram.usesDualFlushTrailingOnlyChrome)
        XCTAssertFalse(ram.usesNotchWingChrome)
        XCTAssertTrue(ram.keepsExpandedWithoutHover)
        XCTAssertTrue(ram.expandsDuringSettingsSession)
        XCTAssertEqual(L10n.ResourceMonitor.tipPercent(96), "96%")
        XCTAssertEqual(L10n.ResourceMonitor.manageTip, "管理")
        XCTAssertEqual(L10n.ResourceMonitor.ramTipLabel, "RAM")

        let solo = IslandNoticeSlotPolicy.applying(incoming: ram, to: IslandNoticeSlots())
        XCTAssertEqual(solo?.secondary?.id, ram.id)
        XCTAssertNil(solo?.primary)
        XCTAssertEqual(solo?.resolvedLayout, .fullNotice(ram))
        XCTAssertTrue(solo?.usesDualFlushChrome == true)
        XCTAssertFalse(solo?.usesDualFlushTrailingOnly == true)
        XCTAssertTrue(solo?.usesDualFlushCompactWings == true)
        XCTAssertEqual(solo?.dualFlushWingWidth, IslandChrome.dualFlushCompactWingWidth)
        XCTAssertFalse(solo?.anyUsesNotchWingChrome == true)
        XCTAssertTrue(solo?.anyKeepsExpandedWithoutHover == true)

        let meeting = IslandNoticePayload.meetingLead(meetingID: "m-with-ram")
        let withB = IslandNoticeSlotPolicy.applying(incoming: meeting, to: solo!)
        XCTAssertEqual(
            withB?.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(ram))
        )
        XCTAssertTrue(withB?.usesDualFlushChrome == true)
        XCTAssertFalse(withB?.usesDualFlushTrailingOnly == true)
    }

    /// 进程结束是 C：单独上岛左右双翼 flush（非仅右半）；与 B 并排居右。
    func test_islandNoticeDualSlots_processEndedUsesDualFlushBothWings() {
        let ended = IslandNoticePayload.processEnded(
            .init(
                id: "projects.watch.test",
                projectName: "ridge-api",
                label: "dev server",
                message: "ridge-api / dev server",
                endedAt: Date(),
                outcome: .succeeded,
                logPath: nil,
                peakMemoryBytes: 420 * 1024 * 1024,
                durationSeconds: 6 * 60 + 12
            )
        )
        XCTAssertEqual(ended.displayLane, .secondary)
        XCTAssertEqual(ended.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertTrue(ended.usesDualFlushSoloChrome)
        XCTAssertFalse(ended.usesDualFlushTrailingOnlyChrome)
        XCTAssertFalse(ended.usesNotchWingChrome)
        XCTAssertTrue(ended.keepsExpandedWithoutHover)
        XCTAssertTrue(ended.expandsDuringSettingsSession)
        XCTAssertEqual(L10n.Projects.tipDuration(6 * 60 + 12), "6m12s")
        XCTAssertEqual(L10n.Projects.exitTag(.succeeded), "exit 0")
        XCTAssertEqual(L10n.Projects.exitTag(.failed(code: 1)), "exit 1")
        XCTAssertEqual(L10n.Projects.exitTag(.signaled(signal: 15)), "SIGTERM")
        XCTAssertEqual(L10n.Projects.exitTag(.signaled(signal: 9)), "SIGKILL")
        XCTAssertEqual(L10n.Projects.exitTag(.signaled(signal: 42)), "sig 42")
        XCTAssertEqual(
            L10n.Projects.outcomeText(.signaled(signal: 15)),
            "被信号终止（SIGTERM）",
            "控制台长文案保留；岛 tip 徽标须短"
        )

        let solo = IslandNoticeSlotPolicy.applying(incoming: ended, to: IslandNoticeSlots())
        XCTAssertEqual(solo?.resolvedLayout, .fullNotice(ended))
        XCTAssertTrue(solo?.usesDualFlushChrome == true)
        XCTAssertFalse(solo?.usesDualFlushTrailingOnly == true)
        XCTAssertTrue(solo?.usesDualFlushCompactWings == true)
        XCTAssertEqual(solo?.dualFlushWingWidth, IslandChrome.dualFlushCompactWingWidth)

        let meeting = IslandNoticePayload.meetingLead(meetingID: "m-with-ended")
        let withB = IslandNoticeSlotPolicy.applying(incoming: meeting, to: solo!)
        XCTAssertEqual(
            withB?.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(ended))
        )
        XCTAssertTrue(withB?.usesDualFlushChrome == true)
    }

    /// 多条非专注 C：FIFO 排队，同时只展示一条；收起后出下一条。
    func test_islandNoticeDualSlots_secondaryTipsQueueFIFO() {
        let ai = IslandNoticePayload.aiUsageAlert(
            id: "ai.queue",
            providerName: "Cursor",
            remainingPercent: 8,
            stage: .warning,
            resetsAt: nil
        )
        let peripheral = IslandNoticePayload.peripheralConnected(
            .init(
                id: "bat.connect.queue",
                deviceID: "airpods-queue",
                deviceName: "AirPods",
                kind: .headphones,
                percent: 80,
                threshold: 0,
                detail: "已连接"
            )
        )
        XCTAssertEqual(ai.autoDismissNanoseconds, 3_000_000_000)
        XCTAssertEqual(peripheral.autoDismissNanoseconds, 3_000_000_000)

        let first = IslandNoticeSlotPolicy.applying(incoming: ai, to: IslandNoticeSlots())
        XCTAssertEqual(first?.secondary?.id, ai.id)
        XCTAssertTrue(first?.secondaryQueue.isEmpty == true)
        XCTAssertEqual(first?.resolvedLayout, .fullNotice(ai))

        let queued = IslandNoticeSlotPolicy.applying(incoming: peripheral, to: first!)
        XCTAssertEqual(queued?.secondary?.id, ai.id, "先到的继续展示")
        XCTAssertEqual(queued?.secondaryQueue.map(\.id), [peripheral.id])

        let next = IslandNoticeSlotPolicy.dismissing(id: ai.id, from: queued!)
        XCTAssertEqual(next.secondary?.id, peripheral.id)
        XCTAssertTrue(next.secondaryQueue.isEmpty)
        XCTAssertEqual(next.resolvedLayout, .fullNotice(peripheral))
    }

    /// 双槽：A 满岛；B+C 左右；多 C FIFO；独占清槽。
    func test_islandNoticeDualSlots_primarySecondaryAndExclusive() {
        let meeting = IslandNoticePayload.meetingLead(meetingID: "dual-m")
        let copy = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.dual",
            text: "已复制",
            symbol: "doc.on.doc"
        )
        let move = IslandNoticePayload.moveReminder(
            .init(id: "move.dual", activeMinutes: 30, restMinutes: 2)
        )
        let exclusive = IslandNoticePayload.ocrSelectTip
        let otherMeeting = IslandNoticePayload.meetingLead(meetingID: "dual-m2")

        let withMeeting = IslandNoticeSlotPolicy.applying(
            incoming: meeting,
            to: IslandNoticeSlots()
        )
        XCTAssertEqual(withMeeting?.primary?.id, meeting.id)
        XCTAssertEqual(withMeeting?.resolvedLayout, .fullNotice(meeting))

        // B + 短 C → 左 B 右 C
        let dual = IslandNoticeSlotPolicy.applying(incoming: copy, to: withMeeting!)
        XCTAssertEqual(dual?.primary?.id, meeting.id)
        XCTAssertEqual(dual?.secondary?.id, copy.id)
        XCTAssertEqual(
            dual?.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy))
        )
        XCTAssertFalse(dual?.anyUsesNotchRightOrbChrome == true)

        // 久坐后来：复制仍展示，久坐入队（FIFO，不再靠 rank 盖掉）
        let moveQueued = IslandNoticeSlotPolicy.applying(incoming: move, to: dual!)
        XCTAssertEqual(moveQueued?.secondary?.id, copy.id)
        XCTAssertEqual(moveQueued?.secondaryQueue.map(\.id), [move.id])

        // 复制收起 → 久坐出队展示
        let restored = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: moveQueued!)
        XCTAssertEqual(restored.secondary?.id, move.id)
        XCTAssertTrue(restored.secondaryQueue.isEmpty)

        // 另一场会议覆盖主槽，次槽保留。
        let swapped = IslandNoticeSlotPolicy.applying(incoming: otherMeeting, to: restored)
        XCTAssertEqual(swapped?.primary?.id, otherMeeting.id)
        XCTAssertEqual(swapped?.secondary?.id, move.id)

        // 独占清通知槽与 C 队列，专注旗标可保留
        var withFocus = swapped!
        withFocus.focusResident = true
        let cleared = IslandNoticeSlotPolicy.applying(incoming: exclusive, to: withFocus)
        XCTAssertEqual(cleared?.primary?.id, exclusive.id)
        XCTAssertNil(cleared?.secondary)
        XCTAssertTrue(cleared?.secondaryQueue.isEmpty == true)
        XCTAssertTrue(cleared?.focusResident == true)
        XCTAssertEqual(cleared?.resolvedLayout, .fullNotice(exclusive))

        XCTAssertNil(IslandNoticeSlotPolicy.applying(incoming: copy, to: cleared!))

        let afterExclusive = IslandNoticeSlotPolicy.dismissing(id: exclusive.id, from: cleared!)
        XCTAssertNil(afterExclusive.primary)
        XCTAssertTrue(afterExclusive.focusResident)
        XCTAssertEqual(afterExclusive.resolvedLayout, .fullFocus)
    }

    /// 专注 / 音乐常驻：独满岛；+短 C 左右并排；C 没后 B/专注回满岛。
    func test_islandNoticeDualSlots_focusResidentLayouts() {
        let meeting = IslandNoticePayload.meetingLead(meetingID: "focus-m")
        let copy = IslandNoticePayload.clipboardCaptureHint(
            id: "copy.focus",
            text: "已复制",
            symbol: "doc.on.doc"
        )

        var focusOnly = IslandNoticeSlots(focusResident: true)
        XCTAssertEqual(focusOnly.resolvedLayout, .fullFocus)

        let focusCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: focusOnly)
        XCTAssertEqual(
            focusCopy?.resolvedLayout,
            .dual(left: .focus, right: .notice(copy))
        )

        let meetingFocus = IslandNoticeSlotPolicy.applying(
            incoming: meeting,
            to: IslandNoticeSlots(focusResident: true)
        )
        XCTAssertEqual(
            meetingFocus?.resolvedLayout,
            .dual(left: .notice(meeting), right: .focus)
        )

        // B 会议满岛中来短 C → 左右；C 没后会议回满岛
        let meetingOnly = IslandNoticeSlotPolicy.applying(incoming: meeting, to: IslandNoticeSlots())
        XCTAssertEqual(meetingOnly?.resolvedLayout, .fullNotice(meeting))
        let meetingCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: meetingOnly!)
        XCTAssertEqual(
            meetingCopy?.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy))
        )
        let meetingBack = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: meetingCopy!)
        XCTAssertEqual(meetingBack.resolvedLayout, .fullNotice(meeting))

        // B 音乐 + 专注 → 左音乐右专注
        var mediaFocus = IslandNoticeSlots(focusResident: true, mediaResident: true)
        XCTAssertEqual(
            mediaFocus.resolvedLayout,
            IslandNoticeLayout.dual(left: .media, right: .focus)
        )
        XCTAssertTrue(mediaFocus.usesDualFlushChrome)

        // 右翼已是专注时来 C → C 盖住专注；C 撤后专注回到右翼
        let mediaFocusCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: mediaFocus)
        XCTAssertEqual(
            mediaFocusCopy?.resolvedLayout,
            IslandNoticeLayout.dual(left: .media, right: .notice(copy))
        )
        XCTAssertTrue(mediaFocusCopy?.focusResident == true)
        let mediaFocusBack = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: mediaFocusCopy!)
        XCTAssertEqual(
            mediaFocusBack.resolvedLayout,
            IslandNoticeLayout.dual(left: .media, right: .focus)
        )

        // 会议 + 专注，右翼来 C → 同理盖住再恢复
        let meetingFocusCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: meetingFocus!)
        XCTAssertEqual(
            meetingFocusCopy?.resolvedLayout,
            IslandNoticeLayout.dual(left: .notice(meeting), right: .notice(copy))
        )
        let meetingFocusBack = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: meetingFocusCopy!)
        XCTAssertEqual(
            meetingFocusBack.resolvedLayout,
            IslandNoticeLayout.dual(left: .notice(meeting), right: .focus)
        )

        // 会议 + 播放 → 会议满岛（盖音乐）
        var meetingMedia = IslandNoticeSlots(mediaResident: true)
        meetingMedia = IslandNoticeSlotPolicy.applying(incoming: meeting, to: meetingMedia)!
        XCTAssertTrue(meetingMedia.mediaResident)
        XCTAssertEqual(meetingMedia.resolvedLayout, .fullNotice(meeting))

        // B 音乐 + 短 C → 左音乐右 C；C 没后音乐满岛
        var mediaSlots = IslandNoticeSlots(mediaResident: true)
        XCTAssertEqual(mediaSlots.resolvedLayout, .fullMedia)
        let mediaCopy = IslandNoticeSlotPolicy.applying(incoming: copy, to: mediaSlots)
        XCTAssertEqual(
            mediaCopy?.resolvedLayout,
            .dual(left: .media, right: .notice(copy))
        )
        // 音乐+复制：双 flush，右 Ø32；禁止会议双翼宽 / 整条黑底包圆岛。
        XCTAssertTrue(mediaCopy?.usesDualFlushChrome == true)
        XCTAssertTrue(mediaCopy?.usesDualFlushWithRightOrb == true)
        XCTAssertFalse(mediaCopy?.anyUsesNotchWingChrome == true)
        XCTAssertFalse(mediaCopy?.anyUsesNotchRightOrbChrome == true)
        let dualFlush = IslandChrome.preparedDualFlushPanelSize(
            notchWidth: 172,
            notchHeight: 32,
            rightIsOrb: true
        )
        let wing = IslandChrome.preparedWingTipPanelSize(notchWidth: 172, notchHeight: 32)
        let dualInsets = IslandChrome.insets(for: .dualFlush, notchHeight: 32)
        let expectedDualW = IslandChrome.dualFlushLeftWingWidth
            + 172
            + IslandChrome.notchRightOrbGap
            + IslandChrome.notchRightOrbDiameter
        let dualOffset = IslandChrome.dualFlushHorizontalOffsetX(rightIsOrb: true)
        // 贴刘海：高=刘海；左翼略宽于 flush、右仅圆岛可留缝；零 inset；偏移为负=往左伸。
        XCTAssertEqual(dualFlush.height, 32)
        XCTAssertEqual(dualFlush.width, expectedDualW)
        XCTAssertGreaterThanOrEqual(
            IslandChrome.dualFlushLeftWingWidth,
            IslandFlushWingStyle.width
        )
        XCTAssertLessThan(
            IslandChrome.dualFlushLeftWingWidth,
            140,
            "左翼过宽会让音符与时长之间空洞过大"
        )
        XCTAssertGreaterThanOrEqual(IslandChrome.dualFlushNotchUnderlap, 10)
        XCTAssertEqual(
            IslandChrome.dualFlushLeftNotchBleed,
            IslandChrome.dualFlushNotchUnderlap
        )
        XCTAssertLessThan(dualFlush.width, wing.width)
        XCTAssertLessThan(dualOffset, 0, "左翼更宽时应左移面板，勿往右顶进刘海")
        XCTAssertEqual(
            dualOffset,
            (IslandChrome.dualFlushRightSideWidth(rightIsOrb: true)
                - IslandChrome.dualFlushLeftWingWidth) / 2
        )
        // 仅圆岛与刘海有缝；非圆岛右翼贴死。
        XCTAssertEqual(
            IslandChrome.dualFlushRightSideWidth(rightIsOrb: true),
            IslandChrome.notchRightOrbGap + IslandChrome.notchRightOrbDiameter
        )
        // 非圆岛右翼与左翼同宽（音乐标准），禁止再缩成 112 胶囊造成左右不对称。
        XCTAssertEqual(
            IslandChrome.dualFlushRightSideWidth(rightIsOrb: false),
            IslandChrome.dualFlushLeftWingWidth
        )
        XCTAssertEqual(
            IslandChrome.dualFlushHorizontalOffsetX(rightIsOrb: false),
            0,
            "左右同宽时应无水平偏移"
        )
        XCTAssertEqual(dualInsets.top, 0)
        XCTAssertEqual(dualInsets.bottom, 0)
        XCTAssertEqual(dualInsets.horizontal, 0)
        let mediaBack = IslandNoticeSlotPolicy.dismissing(id: copy.id, from: mediaCopy!)
        XCTAssertEqual(mediaBack.resolvedLayout, .fullMedia)

        // 会议+复制：双槽走 dualFlush 左右小岛（勿再抬会议双翼宽）
        XCTAssertFalse(meetingCopy?.anyUsesNotchWingChrome == true)
        XCTAssertTrue(meetingCopy?.usesDualFlushChrome == true)

        // 两 B（会议+音乐）：只展示加入会议满岛 tip
        var meetingOverMedia = IslandNoticeSlots(mediaResident: true)
        meetingOverMedia = IslandNoticeSlotPolicy.applying(incoming: meeting, to: meetingOverMedia)!
        meetingOverMedia.mediaResident = true
        XCTAssertEqual(meetingOverMedia.resolvedLayout, .fullNotice(meeting))
        XCTAssertTrue(meetingOverMedia.anyUsesNotchWingChrome)
        XCTAssertFalse(meetingOverMedia.usesDualFlushChrome)

        // 两 B + C：左会议右 C；音乐仍被盖，勿出现左音乐
        let meetingMediaCopy = IslandNoticeSlotPolicy.applying(
            incoming: copy,
            to: meetingOverMedia
        )
        XCTAssertEqual(
            meetingMediaCopy?.resolvedLayout,
            .dual(left: .notice(meeting), right: .notice(copy))
        )
        XCTAssertTrue(meetingMediaCopy?.usesDualFlushChrome == true)
        XCTAssertFalse(meetingMediaCopy?.anyUsesNotchWingChrome == true)
        // C 没后仍回两 B → 只会议
        let meetingMediaBack = IslandNoticeSlotPolicy.dismissing(
            id: copy.id,
            from: meetingMediaCopy!
        )
        XCTAssertEqual(meetingMediaBack.resolvedLayout, .fullNotice(meeting))
        XCTAssertTrue(meetingMediaBack.mediaResident)
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

    /// island-bottom-corner-preview-dead：设置迷你预览须够高以区分 8/18/24（及滑条 32）；矮条会把大半径钳成同形。
    func test_islandBottomCornerPreviewDead_settingsPreviewDistinguishesPresets() {
        let previewH = IslandBottomRadiusPolicy.settingsGeometryPreviewHeight
        let previewW = IslandBottomRadiusPolicy.settingsGeometryPreviewWidth
        XCTAssertGreaterThanOrEqual(
            previewH,
            IslandBottomRadiusPolicy.settingsMaxRadius * 2,
            "迷你预览高度不足时滑条上限会被半高钳死"
        )
        XCTAssertEqual(IslandSettings.Defaults.bottomCornerRadius, 18.0, accuracy: 0.5)
        let flat = IslandBottomRadiusPolicy.clamped(preferred: 8, panelWidth: previewW, panelHeight: previewH)
        let classic = IslandBottomRadiusPolicy.clamped(preferred: 18, panelWidth: previewW, panelHeight: previewH)
        let standard = IslandBottomRadiusPolicy.clamped(preferred: 24, panelWidth: previewW, panelHeight: previewH)
        let sliderMax = IslandBottomRadiusPolicy.clamped(preferred: 32, panelWidth: previewW, panelHeight: previewH)
        XCTAssertEqual(flat, 8, accuracy: 0.5)
        XCTAssertEqual(classic, 18, accuracy: 0.5)
        XCTAssertEqual(standard, 24, accuracy: 0.5)
        XCTAssertEqual(sliderMax, 32, accuracy: 0.5)
        XCTAssertLessThan(flat, classic)
        XCTAssertLessThan(classic, standard)
        XCTAssertLessThan(standard, sliderMax)

        // 旧 24pt 矮预览：18/24/32 全部钳成 12，调了「没反应」。
        let deadH: CGFloat = 24
        let deadClassic = IslandBottomRadiusPolicy.clamped(preferred: 18, panelWidth: previewW, panelHeight: deadH)
        let deadRound = IslandBottomRadiusPolicy.clamped(preferred: 32, panelWidth: previewW, panelHeight: deadH)
        XCTAssertEqual(deadClassic, deadRound, accuracy: 0.5)

        // 真岛：非控制台跟设置；控制台有 26 下限；圆岛固定半径。
        let tall = IslandBottomRadiusPolicy.applied(
            settingsRadius: 8,
            isNotchRightOrb: false,
            isControlDeckPage: false,
            panelWidth: 400,
            panelHeight: 120
        )
        XCTAssertEqual(tall, 8, accuracy: 0.5)
        let deck = IslandBottomRadiusPolicy.applied(
            settingsRadius: 8,
            isNotchRightOrb: false,
            isControlDeckPage: true,
            panelWidth: 400,
            panelHeight: 120
        )
        XCTAssertEqual(deck, IslandBottomRadiusPolicy.controlDeckFloor, accuracy: 0.5)
        let orb = IslandBottomRadiusPolicy.applied(
            settingsRadius: 8,
            isNotchRightOrb: true,
            isControlDeckPage: false,
            panelWidth: 32,
            panelHeight: 32
        )
        XCTAssertEqual(orb, IslandChrome.notchRightOrbDiameter / 2, accuracy: 0.5)
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

    /// meeting-tip-stays-after-join：入会后即使 latch 未清，也不得再选同一场。
    func test_meetingTipAfterJoin_skipsDismissedEvenIfStillLatched() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingEvent(
            id: "m-join",
            title: "已入会场",
            startDate: now.addingTimeInterval(3 * 60),
            endDate: now.addingTimeInterval(33 * 60),
            calendarIdentifier: "cal",
            calendarTitle: "日历",
            join: nil
        )
        let stillLatched = MeetingLeadTipSelector.Input(
            now: now,
            leadSeconds: 10 * 60,
            tipDismissMode: .afterMinutes,
            tipDismissMinutes: 5,
            dismissedAfterJoinID: meeting.id,
            latchedMeetingID: meeting.id
        )
        XCTAssertNil(
            MeetingLeadTipSelector.select(from: [meeting], input: stillLatched),
            "入会后 tip 须消失：dismissed 优先于 latch"
        )
    }

    /// meeting-tip-stays-after-join：会话级 join 须立刻撤 tip，且后续 publish 不得贴回同一场。
    @MainActor
    func test_meetingTipAfterJoin_sessionDismissesAndRejectsRepublish() {
        let session = MeetingLeadSession.shared
        session.resetForTests()
        IslandNoticeCenter.shared.dismiss(id: nil)
        defer {
            session.resetForTests()
            IslandNoticeCenter.shared.dismiss(id: nil)
        }

        var openedURLs: [URL] = []
        session.openURLHandler = { url in
            openedURLs.append(url)
            return true
        }

        let meetingID = "m-session-join"
        let joinURL = URL(string: "https://zoom.us/j/123456789")!
        let now = Date()
        let snap = MeetingLeadSession.Snapshot(
            meetingID: meetingID,
            title: "入会后须撤 tip",
            startDate: now.addingTimeInterval(3 * 60),
            endDate: now.addingTimeInterval(33 * 60),
            secondsToStart: 3 * 60,
            showJoin: true,
            showAuth: false,
            joinOpenURL: joinURL,
            joinSourceURL: joinURL,
            joinPlatform: "zoom"
        )
        session.publish(snap, reason: "testPresent")
        XCTAssertEqual(session.snapshot?.meetingID, meetingID)
        XCTAssertEqual(IslandNoticeCenter.shared.current?.id, "meeting.lead.\(meetingID)")

        session.joinFromNotice()
        XCTAssertEqual(openedURLs, [joinURL])
        XCTAssertEqual(session.dismissedAfterJoinID, meetingID)
        XCTAssertNil(session.snapshot, "入会后快照须清空")
        XCTAssertNotEqual(
            IslandNoticeCenter.shared.current?.id,
            "meeting.lead.\(meetingID)",
            "入会后岛上须撤回会前提示"
        )

        // 模拟 widget tick / joinedAdvance 再次投递同一场：须拒收。
        session.publish(snap, reason: "tick")
        XCTAssertNil(session.snapshot, "已入会场次不得再 present")
        XCTAssertEqual(session.dismissedAfterJoinID, meetingID)
        XCTAssertNotEqual(
            IslandNoticeCenter.shared.current?.id,
            "meeting.lead.\(meetingID)"
        )
    }

    /// meeting-tip-stays-after-join：open 失败也必须撤 tip 并打 dismissed。
    @MainActor
    func test_meetingTipAfterJoin_openFailureStillDismissesTip() {
        let session = MeetingLeadSession.shared
        session.resetForTests()
        IslandNoticeCenter.shared.dismiss(id: nil)
        defer {
            session.resetForTests()
            IslandNoticeCenter.shared.dismiss(id: nil)
        }

        session.openURLHandler = { _ in false }

        let meetingID = "m-open-fail"
        let joinURL = URL(string: "https://meeting.tencent.com/dm/abc")!
        let now = Date()
        session.publish(
            .init(
                meetingID: meetingID,
                title: "打开失败仍撤",
                startDate: now.addingTimeInterval(2 * 60),
                endDate: now.addingTimeInterval(32 * 60),
                secondsToStart: 2 * 60,
                showJoin: true,
                showAuth: false,
                joinOpenURL: joinURL,
                joinSourceURL: joinURL,
                joinPlatform: "tencent"
            ),
            reason: "testPresent"
        )
        XCTAssertNotNil(session.snapshot)

        session.joinFromNotice()
        XCTAssertEqual(session.dismissedAfterJoinID, meetingID)
        XCTAssertNil(session.snapshot)
        XCTAssertNotEqual(
            IslandNoticeCenter.shared.current?.id,
            "meeting.lead.\(meetingID)"
        )
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

    /// 媒体/会议操作钮须抬高可点下限；矮框会导致「矫枉后点不中」。
    func test_islandFocusSteal_mediaAndControlDeckFloorsAreTallEnoughToClick() {
        let media = MediaExpandedContentSize.panelSize()
        XCTAssertGreaterThan(media.height, NotchGeometry.compactIslandHeight + 80)
        XCTAssertGreaterThanOrEqual(MediaExpandedContentSize.minContentHeight, 140)
        XCTAssertEqual(NotchGeometry.controlDeckMinHeight, 300)
        XCTAssertEqual(NotchGeometry.controlDeckPreferredWidth, 660)
        // 控制台展开地板须高于保展开下限，否则仍可能「移一半就收」。
        let floor = IslandExpandedPanelPolicy.expandedRetentionFloor(
            notch: CGSize(width: 179, height: 32)
        )
        XCTAssertGreaterThanOrEqual(NotchGeometry.controlDeckMinHeight, floor.height)
    }

    // MARK: - settings-preview-live-data（股票样张条数）

    func test_settingsPreviewLiveData_stockSampleUsesFixedFakePair() {
        // 库卡/详情必须假数据固定两卡，禁止实时行情空态。
        let sample = StockIslandView.previewSnapshots()
        XCTAssertEqual(sample.count, 2, "股票设置预览样张必须固定 2 条")
    }

    /// 设置预览入口须走假数据分支，禁止库卡/详情依赖实时空源。
    @MainActor
    func test_settingsPreviewLiveData_widgetSamplePreviewUsesFakeSamples() {
        XCTAssertEqual(BatteryDeckView.sampleDevices.count, 2)
        XCTAssertFalse(BatteryDeckView.sampleDevices.isEmpty)
        // 媒体 / 会议 / 番茄预览样张可构造且非空标题。
        let media = MediaIslandCardView.previewSample(animatedEqualizer: false)
        XCTAssertFalse(media.title.isEmpty)
        let meeting = MeetingIslandCardView.previewSample(urgency: .relaxed, compact: true)
        XCTAssertFalse(meeting.title.isEmpty)
        XCTAssertTrue(WidgetSamplePreview.hugsIslandContent(for: "system.controlDeck.battery"))
        XCTAssertTrue(WidgetSamplePreview.contentProvidesOpaqueShell(for: "system.controlDeck.battery"))
        // 股票固定两卡（与上条一致，防止只测 snapshot 漏入口）。
        XCTAssertEqual(StockIslandView.previewSnapshots().count, 2)
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
        // 库卡：黑岛统一同比到 290（灰舞台不缩）；「已复制」除外。
        XCTAssertEqual(SettingsIslandPreviewWidth.library, 290)
        XCTAssertEqual(SettingsIslandPreviewWidth.libraryScale(nativeWidth: 580), 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(
            SettingsIslandPreviewWidth.libraryScale(nativeWidth: 200),
            1,
            "短于 290 的样张亦同比拉到 290"
        )
        let nativeW = BatteryDeckIslandPreview.nativePanelSize().width
        let scale = BatteryDeckIslandPreview.libraryPreviewScale
        XCTAssertLessThan(scale, 1, "双卡样张固有宽超过 library，库卡须缩小黑岛")
        XCTAssertEqual(
            nativeW * scale,
            SettingsIslandPreviewWidth.library,
            accuracy: 0.5
        )
        XCTAssertFalse(
            WidgetSamplePreview.scalesBlackIslandToLibraryWidth(for: "builtin.copiedNotice")
        )
        XCTAssertTrue(
            WidgetSamplePreview.scalesBlackIslandToLibraryWidth(for: "system.controlDeck.battery")
        )
    }

    // MARK: - settings-preview-island-width（媒体 / 番茄预览黑岛宽统一；tip 必须 hugs）

    @MainActor
    func test_settingsPreviewIslandWidth_tipAndMediaFocusAligned() {
        // 详情 tip=360；库卡 library=290；媒体/番茄详情 standby/expanded=380。
        XCTAssertEqual(SettingsIslandPreviewWidth.tip, 360)
        XCTAssertEqual(SettingsIslandPreviewWidth.library, 290)
        XCTAssertEqual(SettingsIslandPreviewWidth.standby, SettingsIslandPreviewWidth.expanded)
        XCTAssertEqual(SettingsIslandPreviewWidth.standby, 380)
        XCTAssertEqual(SettingsIslandPreviewWidth.tipBarHeight, 30)
        XCTAssertNil(WidgetSamplePreview.libraryIslandWidth(for: "builtin.meeting"))
        XCTAssertNil(WidgetSamplePreview.libraryIslandWidth(for: "builtin.media"))
        XCTAssertNil(WidgetSamplePreview.libraryIslandWidth(for: "builtin.focusTimer"))
        XCTAssertEqual(
            WidgetSamplePreview.libraryIslandWidth(for: "system.controlDeck.volume"),
            NotchGeometry.controlDeckPreferredWidth
        )
        XCTAssertEqual(
            WidgetSamplePreview.detailIslandWidth(for: "system.controlDeck.shelf"),
            NotchGeometry.controlDeckPreferredWidth
        )
        XCTAssertNil(WidgetSamplePreview.detailIslandWidth(for: "builtin.media"))
        // 库卡才缩到 290；详情舞台不套 library 缩放。
        XCTAssertTrue(WidgetSamplePreview.scalesBlackIslandToLibraryWidth(for: "builtin.media"))
        XCTAssertTrue(WidgetSamplePreview.scalesBlackIslandToLibraryWidth(for: "system.controlDeck.battery"))
        XCTAssertFalse(WidgetSamplePreview.scalesBlackIslandToLibraryWidth(for: "builtin.copiedNotice"))
        XCTAssertNotEqual(NotchGeometry.mediaCompactWidth, NotchGeometry.focusTimerCompactWidth)
    }

    // MARK: - settings-preview-tip-forced-stretch（tip 预览禁强制拉宽 / 番茄禁 minStageHeight 撑高黑岛）

    @MainActor
    func test_settingsPreviewTipForcedStretch_tipsMustHugAndChromeFixed() {
        XCTAssertTrue(
            WidgetSamplePreview.tipPreviewHugsContent,
            "tip 详情 hugsContent 须为 true，禁止拉满 maxIslandWidth 撑开左右空档"
        )
        let tipIDs: [WidgetID] = [
            "builtin.meeting",
            "builtin.aiUsage",
            "builtin.moveReminder",
            "builtin.colorPick",
            "builtin.ocrSelect",
            "builtin.peripheralTip",
            "builtin.peripheralTip.low",
            "builtin.peripheralTip.full",
            "builtin.peripheralTip.connect",
            "builtin.macBatteryTip",
            "builtin.macBatteryTip.charging",
            "builtin.macBatteryTip.low",
            "builtin.macBatteryTip.full",
            "builtin.macBatteryTip.unplugged",
            "builtin.networkLinkTip",
            "builtin.networkLinkTip.wifiConnected",
            "builtin.networkLinkTip.wiredConnected",
            "builtin.networkLinkTip.vpnConnected",
            "builtin.networkLinkTip.wifiDisconnected",
            "builtin.networkLinkTip.vpnDisconnected",
        ]
        for id in tipIDs {
            XCTAssertTrue(
                WidgetSamplePreview.hugsIslandContent(for: id),
                "\(id) 库卡预览须 hugs，翼宽与 chrome 定死"
            )
            XCTAssertNil(
                WidgetSamplePreview.libraryIslandWidth(for: id),
                "\(id) 不得强制 libraryIslandWidth，否则左右间距被拉大"
            )
        }
        // tip 左右边距令牌不得漂移（与 island-chrome-double-padding 同值）。
        XCTAssertEqual(IslandChrome.contentHorizontal, 7)
        XCTAssertEqual(IslandChrome.compactTipBottom, 4)
        // 媒体/番茄可固定预览宽，但高度须贴内容（stageCanvas 不得把 minStageHeight 作用在黑岛上）。
        XCTAssertTrue(
            WidgetSamplePreview.hugsIslandContent(for: "builtin.focusTimer"),
            "专注待命预览与会议 tip 同 hugs"
        )
        XCTAssertNil(WidgetSamplePreview.libraryIslandWidth(for: "builtin.focusTimer"))
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
        // 电量预览自带岛底；库卡缩放后宽须落到 library，避免发闷大黑岛。
        let native = BatteryDeckIslandPreview.nativePanelSize()
        XCTAssertGreaterThan(native.width, SettingsIslandPreviewWidth.library)
        XCTAssertEqual(
            native.width * BatteryDeckIslandPreview.libraryPreviewScale,
            SettingsIslandPreviewWidth.library,
            accuracy: 0.5
        )
    }

    // MARK: - volume adaptive height（控制台混音台）

    func test_controlDeckVolumeHeight_adaptsBelowMaxAndCapsAtMax() {
        let maxPanel = NotchGeometry.controlDeckMinHeight
        let sparse = ControlDeckContentSize.volumePanelHeight(deviceCount: 1, appCount: 0)
        let dense = ControlDeckContentSize.volumePanelHeight(deviceCount: 5, appCount: 7)
        XCTAssertLessThanOrEqual(sparse, maxPanel, "内容少时不超过最大高度")
        XCTAssertEqual(dense, maxPanel, "内容多时不得超过原最大高度")
        XCTAssertGreaterThanOrEqual(sparse, ControlDeckContentSize.volumePanelMinHeight)
        XCTAssertEqual(ControlDeckContentSize.volumePanelMinHeight, 230)
    }

    /// 混音台 applyRoute 必须用宿主 key；进程自身 `.helper` bundle 对不上 UI 行。
    func test_soundAppVolumeHostKey_helperBundleDoesNotEqualHostKey() {
        let helper = "com.soda.music.helper"
        let hosts = SoundHostAppResolver.parentBundleIDCandidates(helper)
        XCTAssertTrue(hosts.contains("com.soda.music"), "Helper 应剥到宿主 bundle")
        XCTAssertFalse(hosts.contains(helper))
        // 旧逻辑 `process.bundleID == key` 在 key=宿主 时永远空匹配。
        XCTAssertNotEqual(helper, "com.soda.music")
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

    /// 提示 / 实况 / 面板库卡灰舞台与整卡高度一律一致。
    func test_widgetLibraryCard_livePanelShareTipChrome() {
        XCTAssertEqual(WidgetLibraryCardLayout.islandStageHeight, 106)
        XCTAssertEqual(WidgetLibraryCardLayout.cardHeight, 196)
        XCTAssertEqual(
            WidgetLibraryCardLayout.islandStageHeight(for: .tip),
            WidgetLibraryCardLayout.islandStageHeight(for: .live)
        )
        XCTAssertEqual(
            WidgetLibraryCardLayout.islandStageHeight(for: .live),
            WidgetLibraryCardLayout.islandStageHeight(for: .panel)
        )
        XCTAssertEqual(
            WidgetLibraryCardLayout.cardHeight(for: .tip),
            WidgetLibraryCardLayout.cardHeight(for: .panel)
        )
        XCTAssertEqual(SettingsIslandPreviewWidth.tipStageMinHeight, 88)
        // 详情 tip/待命灰区与库卡令牌对齐，避免各页再写 96/100/120。
        XCTAssertEqual(
            SettingsIslandPreviewWidth.tipStageMinHeight,
            88,
            "详情 tip/待命 minStageHeight 须统一"
        )
    }

    func test_widgetLibraryFamily_displayOrderIsTipLivePanel() {
        XCTAssertEqual(
            WidgetLibraryFamily.displayOrder,
            [.tip, .live, .panel]
        )
    }

    /// 库页扁平默认序不变；开发者卡仅 UI 沉底分区。
    func test_widgetLibraryLayout_flatDefaultOrder() {
        let order = WidgetLibraryLayout.defaultFlatDisplayOrder
        XCTAssertEqual(order.first, "builtin.copiedNotice")
        let focus = order.firstIndex(of: "builtin.focusTimer")!
        let shelf = order.firstIndex(of: "system.controlDeck.shelf")!
        XCTAssertEqual(focus + 1, shelf)
        let peripheral = order.firstIndex(of: "builtin.peripheralTip")!
        let macBattery = order.firstIndex(of: "builtin.macBatteryTip")!
        let network = order.firstIndex(of: "builtin.networkLinkTip")!
        let media = order.firstIndex(of: "builtin.media")!
        XCTAssertEqual(peripheral + 1, macBattery)
        XCTAssertEqual(macBattery + 1, network)
        XCTAssertEqual(network + 1, media)
        XCTAssertEqual(media + 1, focus)
        XCTAssertEqual(order[order.count - 2], "system.controlDeck.volume")
        XCTAssertEqual(order.last, "system.controlDeck.projects")
        XCTAssertEqual(order[2], "builtin.aiUsage")
        XCTAssertTrue(WidgetLibraryLayout.isDeveloperWidget("builtin.aiUsage"))
        XCTAssertTrue(WidgetLibraryLayout.isDeveloperWidget("system.controlDeck.projects"))
        XCTAssertFalse(WidgetLibraryLayout.isDeveloperWidget("builtin.meeting"))
        XCTAssertEqual(
            WidgetLibraryLayout.defaultContentOrder,
            [
                "builtin.copiedNotice",
                "builtin.meeting",
                "builtin.aiUsage",
                "builtin.moveReminder",
                "builtin.colorPick",
                "builtin.ocrSelect",
                "builtin.peripheralTip",
                "builtin.macBatteryTip",
                "builtin.networkLinkTip",
                "builtin.media",
                "builtin.focusTimer",
                "builtin.worldClock",
                "builtin.stocks",
            ]
        )
    }

    func test_widgetLibraryFamily_mapsKnownWidgets() {
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.meeting"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.peripheralTip"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.macBatteryTip"), .tip)
        XCTAssertEqual(WidgetLibraryFamily.family(for: "builtin.networkLinkTip"), .tip)
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
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.macBatteryTip"))
        XCTAssertFalse(WidgetLibraryFamily.allowsIslandContentPage("builtin.networkLinkTip"))
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

    /// 媒体展开下限须高于小岛，否则底栏暂停/切歌落在 interactiveFrame 外。
    func test_mediaExpandedContentSize_tallerThanCompactIsland() {
        let panel = MediaExpandedContentSize.panelSize()
        XCTAssertGreaterThan(panel.height, NotchGeometry.mediaCompactHeight + 40)
        XCTAssertEqual(
            panel.width,
            MediaExpandedContentSize.contentWidth + IslandChrome.horizontalInsetTotal,
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(MediaExpandedContentSize.minContentHeight, 140)
    }

    /// 媒体设置预览：收起贴真岛定高；展开顶用可见 inset（>0），底=contentBottom。
    func test_mediaPreviewChrome_matchesLiveIslandInsets() {
        XCTAssertEqual(MediaPreviewChrome.compactHorizontal, 10)
        XCTAssertEqual(
            MediaPreviewChrome.compactContentHeight,
            max(0, NotchGeometry.mediaCompactHeight - 4),
            accuracy: 0.5
        )
        XCTAssertEqual(
            MediaPreviewChrome.expandedTop,
            IslandChrome.previewExpandedVisibleTopInset(),
            accuracy: 0.5
        )
        XCTAssertGreaterThan(MediaPreviewChrome.expandedTop, 0)
        XCTAssertEqual(MediaPreviewChrome.expandedBottom, IslandChrome.contentBottom)
        XCTAssertEqual(MediaPreviewChrome.expandedHorizontal, IslandChrome.contentHorizontal)
        // 真岛面板下限 = 顶空隙 + 内容 + 底距；预览顶距另走 MediaPreviewChrome.expandedTop。
        let panel = MediaExpandedContentSize.panelSize()
        XCTAssertEqual(MediaExpandedContentSize.topInset, 4, accuracy: 0.5)
        XCTAssertEqual(
            panel.height,
            MediaExpandedContentSize.topInset
                + MediaExpandedContentSize.minContentHeight
                + IslandChrome.contentBottom,
            accuracy: 0.5
        )
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
        // 顺延 +10m/+15m 比 +5m 加宽，避免待命右簇被裁。
        XCTAssertEqual(
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 5),
            NotchGeometry.focusTimerCompactWidth,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 10),
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 5)
        )
        XCTAssertEqual(
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 10),
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 15),
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(
            NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 10)
                - NotchGeometry.focusTimerStandbyWidth(extendStepMinutes: 5),
            20
        )
        // 正计时：分秒档与倒计时待命同宽，避免 MM:SS 被裁；出小时再加宽；不足 1 分仍按分秒占位。
        XCTAssertEqual(
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 45),
            NotchGeometry.focusTimerCompactWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 90),
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 45),
            accuracy: 0.5
        )
        XCTAssertEqual(
            NotchGeometry.focusTimerCountUpClockMinWidth(elapsedSeconds: 45),
            NotchGeometry.focusTimerCountUpClockMinWidthMMSS,
            accuracy: 0.5
        )
        XCTAssertEqual(
            NotchGeometry.focusTimerCountUpClockMinWidth(elapsedSeconds: 3600),
            NotchGeometry.focusTimerCountUpClockMinWidthHHMMSS,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3600),
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3599)
        )
        XCTAssertEqual(
            NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3600)
                - NotchGeometry.focusTimerCountUpStandbyWidth(elapsedSeconds: 3599),
            NotchGeometry.focusTimerCountUpHoursExtraWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(
            FocusTimerFormatting.countUpClock(45),
            "45"
        )
        XCTAssertEqual(
            FocusTimerFormatting.countUpClock(90),
            "01:30"
        )
        XCTAssertEqual(
            FocusTimerFormatting.countUpClock(1 * 3600 + 27 * 60 + 32),
            "01:27:32"
        )
        // 库卡待命外框 290×30（详情另走 standby）；环径令牌保留供双翼小标对齐参考。
        XCTAssertEqual(FocusTimerCompactMetrics.progressRingDiameter, 22)
        XCTAssertEqual(SettingsIslandPreviewWidth.library, 290)
        XCTAssertEqual(SettingsIslandPreviewWidth.tipBarHeight, 30)
        XCTAssertEqual(SettingsIslandPreviewWidth.tip, 360)
    }

    /// 收起高度必须等于刘海高：贴顶时底边齐平，禁止固定 38 抬高掉出刘海。
    func test_compactIsland_heightMatchesNotchBottomAlignment() {
        for notchH: CGFloat in [30, 32, 33, 37] {
            let h = NotchGeometry.compactPanelHeight(notchHeight: notchH)
            XCTAssertEqual(h, notchH, accuracy: 0.5, "notchH=\(notchH)")
            XCTAssertLessThanOrEqual(h, notchH + 0.5)
        }
        // 预览 fallback 不得高于常见刘海，否则设置样张也会「掉底」。
        XCTAssertLessThanOrEqual(NotchGeometry.compactIslandHeight, 34)
        XCTAssertEqual(
            MediaPreviewChrome.compactContentHeight,
            max(0, NotchGeometry.compactPanelHeight(notchHeight: NotchGeometry.compactIslandHeight) - 4),
            accuracy: 0.5
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

    /// media-compact-not-resident：左翼/刘海开媒体；右专注翼排除；仅专注翼不算。
    func test_mediaCompactNotResident_dualWingHoverCountsAsExpand() {
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: false,
                pointerOverCompactPanel: true,
                mediaCompactVisible: true,
                hoverExpandSuppressed: false,
                pointerOverFocusTrailingWing: false
            ),
            "播放小岛可见时悬停左翼须能开媒体"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: false,
                pointerOverCompactPanel: true,
                mediaCompactVisible: true,
                hoverExpandSuppressed: false,
                pointerOverFocusTrailingWing: true
            ),
            "右专注翼不得因悬停开媒体（留给 +Nm/暂停）"
        )
        XCTAssertTrue(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: true,
                pointerOverCompactPanel: false,
                mediaCompactVisible: true,
                hoverExpandSuppressed: false,
                pointerOverFocusTrailingWing: false
            ),
            "悬停刘海仍须展开"
        )
        // 刘海命中优先；即便误标 trailing 也不应挡刘海（调用方应保证互斥，闸门仍以 trailing 为准）。
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: true,
                pointerOverCompactPanel: false,
                mediaCompactVisible: true,
                hoverExpandSuppressed: false,
                pointerOverFocusTrailingWing: true
            ),
            "右翼标记时即便 notchHover 也不开媒体"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: false,
                pointerOverCompactPanel: true,
                mediaCompactVisible: false,
                hoverExpandSuppressed: false
            ),
            "仅专注待命翼不得因悬停开媒体"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.shouldExpandCollapsedForMediaCompact(
                notchHover: false,
                pointerOverCompactPanel: true,
                mediaCompactVisible: true,
                hoverExpandSuppressed: true
            ),
            "拖文件松手冷却中不得展开"
        )

        let notch = CGRect(x: 100, y: 0, width: 200, height: 32)
        XCTAssertTrue(
            IslandExpandedPanelPolicy.isPointerOverMediaFocusTrailingWing(
                mouse: CGPoint(x: 320, y: 16),
                notchFrame: notch,
                mediaFocusDualVisible: true
            )
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isPointerOverMediaFocusTrailingWing(
                mouse: CGPoint(x: 80, y: 16),
                notchFrame: notch,
                mediaFocusDualVisible: true
            ),
            "左翼不算专注 trailing"
        )
        XCTAssertFalse(
            IslandExpandedPanelPolicy.isPointerOverMediaFocusTrailingWing(
                mouse: CGPoint(x: 320, y: 16),
                notchFrame: notch,
                mediaFocusDualVisible: false
            ),
            "非双翼时不算"
        )
    }
}
