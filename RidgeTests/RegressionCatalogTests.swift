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
        // 入场约 0.9s + 定格 0.5s，勿再挂满 3s。
        XCTAssertEqual(
            copied.autoDismissNanoseconds,
            IslandChrome.notchRightOrbAutoDismissNanoseconds
        )
        XCTAssertEqual(IslandChrome.notchRightOrbLingerNanoseconds, 500_000_000)
        XCTAssertTrue(copied.holdsWhileHovering)

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
        let clamped = IslandPanelSizing.clamp(
            orb,
            notchWidth: 160,
            notchHeight: 32,
            maxWidth: 2000
        )
        XCTAssertEqual(clamped.width, IslandChrome.notchRightOrbDiameter)
        XCTAssertEqual(clamped.height, IslandChrome.notchRightOrbDiameter)
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
        let orb = IslandChrome.insets(for: .notchRightOrb, notchHeight: notchH)

        // 展开 / 翼 / 短 tip / 普通通知：左右边距同一固定令牌。
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
        // 「已复制」圆岛：内容自撑 Ø32，壳层零 inset。
        XCTAssertEqual(orb.top, 0)
        XCTAssertEqual(orb.bottom, 0)
        XCTAssertEqual(orb.horizontal, 0)
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
        XCTAssertEqual(IslandChrome.contentHorizontal, 14)
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

    /// 库页扁平：已复制第一；货架紧接专注计时之后；音量倒数第二；项目最后。
    func test_widgetLibraryLayout_flatDefaultOrder() {
        let order = WidgetLibraryLayout.defaultFlatDisplayOrder
        XCTAssertEqual(order.first, "builtin.copiedNotice")
        let focus = order.firstIndex(of: "builtin.focusTimer")!
        let shelf = order.firstIndex(of: "system.controlDeck.shelf")!
        XCTAssertEqual(focus + 1, shelf)
        let peripheral = order.firstIndex(of: "builtin.peripheralTip")!
        let media = order.firstIndex(of: "builtin.media")!
        XCTAssertEqual(peripheral + 1, media)
        XCTAssertEqual(media + 1, focus)
        XCTAssertEqual(order[order.count - 2], "system.controlDeck.volume")
        XCTAssertEqual(order.last, "system.controlDeck.projects")
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
        // 真岛面板下限仍只含底距（运行时顶 0）；预览顶距另走 MediaPreviewChrome.expandedTop。
        let panel = MediaExpandedContentSize.panelSize()
        XCTAssertEqual(
            panel.height,
            MediaExpandedContentSize.minContentHeight + IslandChrome.contentBottom,
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
        // 专注左环须与媒体封面同径；库卡待命外框 290×30（详情另走 standby）。
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
}
