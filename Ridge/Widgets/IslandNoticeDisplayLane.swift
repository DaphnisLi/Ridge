import Foundation

/// 岛展示四档（产品 A/B/C/D；高 → 低）见 `docs/PRODUCT.md` §3：
///
/// | 档 | 成员 | 本文件锚点 |
/// |---|---|---|
/// | **A** | 取色 / 框选 | `exclusive` |
/// | **B** | 会议 / 正在播放 | 会议 `primary`；`mediaResident` |
/// | **C** | 下载 / 计时 | `downloadResident`；`focusResident`（下载 > 计时） |
/// | **D** | 瞬时 tip（含系统专注） | `secondary` FIFO |
///
/// 形态摘要：
/// - A → 满岛独占（清 D 队列）
/// - B 会议盖播放；会议 + C → 左会议 · 右下载或计时
/// - B 播放 + C 下载 → 左音乐 · 右下载（下完再露计时）
/// - C 内：下载 + 计时 → 左下载 · 右计时；仅下载 → 全岛
/// - 左 B/C + 右 D；D 暂盖右翼约 3s
///
/// 多条 D：**FIFO**，同时只一条。凡 `.dual` 一律 **dualFlush**。
enum IslandNoticeDisplayLane: Int, Equatable, Comparable {
    /// 产品 **D**（瞬时 tip）
    case secondary = 0
    /// 产品 **B** 中的会议 tip
    case primary = 1
    /// 产品 **A**（取色 / 框选）
    case exclusive = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 解析后的展示方案（驱动壳层 / 卡片）。
enum IslandNoticeLayout: Equatable {
    case empty
    case fullNotice(IslandNoticePayload)
    case fullFocus
    case fullMedia
    case fullDownload
    case dual(left: IslandNoticeLayoutSide, right: IslandNoticeLayoutSide)
}

enum IslandNoticeLayoutSide: Equatable {
    case notice(IslandNoticePayload)
    case focus
    case media
    case download
}

/// 主 / 次 / 常驻旗标快照。
struct IslandNoticeSlots: Equatable {
    /// **B** 会议 tip 等；音乐不走 payload，见 `mediaResident`。
    var primary: IslandNoticePayload?
    /// 当前可见的 **D**（瞬时 tip；靠右或单独满岛）。
    var secondary: IslandNoticePayload?
    /// 等待中的 D（FIFO）。
    var secondaryQueue: [IslandNoticePayload] = []
    /// **C** 计时进行中（有 B 时居右；被 D / 同档下载暂盖后会回到右翼）。
    var focusResident: Bool = false
    /// **B** 音乐播放中（同档会议在时满岛盖住音乐）。
    var mediaResident: Bool = false
    /// **C** 浏览器下载常驻（同档内高于计时；与 B 并排占右；单独=全岛）。
    var downloadResident: Bool = false

    var current: IslandNoticePayload? { primary ?? secondary }

    var isEmpty: Bool {
        primary == nil && secondary == nil && secondaryQueue.isEmpty
            && !focusResident && !mediaResident && !downloadResident
    }

    var hasNoticePayload: Bool {
        primary != nil || secondary != nil
    }

    /// 通知页需要上岛：有 tip，或 B 音乐与 C 并排。
    var needsNoticePage: Bool {
        hasNoticePayload
    }

    var ids: [String] {
        ([primary?.id, secondary?.id].compactMap { $0 }) + secondaryQueue.map(\.id)
    }

    func contains(id: String) -> Bool {
        primary?.id == id
            || secondary?.id == id
            || secondaryQueue.contains(where: { $0.id == id })
    }

    var anyKeepsExpandedWithoutHover: Bool {
        (primary?.keepsExpandedWithoutHover == true)
            || (secondary?.keepsExpandedWithoutHover == true)
    }

    /// 槽内是否有「设置会话中仍可程序展开」的瞬时 tip。
    var anyExpandsDuringSettingsSession: Bool {
        (primary?.expandsDuringSettingsSession == true)
            || (secondary?.expandsDuringSettingsSession == true)
    }

    var anyUsesNotchWingChrome: Bool {
        switch resolvedLayout {
        case .fullFocus, .fullMedia, .fullDownload, .dual, .empty:
            // 双槽一律左右 flush 小岛，勿抬会议双翼宽；单独专注/音乐不走翼 tip。
            return false
        case .fullNotice(let p):
            // 仅「满岛单 tip」（如只有会议 / 两 B 时只留会议）才用双翼壳。
            return p.usesNotchWingChrome
        }
    }

    /// 当前满岛翼 tip 是否外设窄翼（预备宽 / 可点区抬升须对齐，禁止再抬成会议翼）。
    var anyUsesCompactPeripheralWing: Bool {
        switch resolvedLayout {
        case .fullNotice(let p):
            return p.usesCompactPeripheralWing
        default:
            return false
        }
    }

    /// 当前满岛翼 tip 是否网络略收翼。
    var anyUsesNetworkLinkWing: Bool {
        switch resolvedLayout {
        case .fullNotice(let p):
            return p.usesNetworkLinkWing
        default:
            return false
        }
    }

    /// 当前翼 tip 预备单侧翼宽。
    var wingTipPreparedWingWidth: CGFloat {
        if anyUsesCompactPeripheralWing {
            return IslandChrome.preparedPeripheralWingWidth
        }
        if anyUsesNetworkLinkWing {
            return IslandChrome.preparedNetworkLinkWingWidth
        }
        return IslandChrome.preparedWingWidth
    }

    /// 任意 `.dual` 都走贴刘海左右 flush；单独进程结束等走 dualFlush 双翼。
    var usesDualFlushChrome: Bool {
        if case .dual = resolvedLayout { return true }
        if case .fullNotice(let payload) = resolvedLayout {
            return payload.usesDualFlushSoloChrome
        }
        return false
    }

    /// 双槽且右侧是「已复制」Ø32：左翼可加宽，右翼不要再铺整块黑底。
    var usesDualFlushWithRightOrb: Bool {
        guard usesDualFlushChrome,
              case .dual(_, let right) = resolvedLayout,
              case .notice(let payload) = right
        else { return false }
        return payload.usesNotchRightOrbChrome
    }

    /// 单独 tip 只要右翼半块时跳过左翼黑底；当前无此态（RAM 单独走整块翼）。
    var usesDualFlushTrailingOnly: Bool {
        guard case .fullNotice(let payload) = resolvedLayout else { return false }
        return payload.usesDualFlushTrailingOnlyChrome
    }

    /// RAM / 进程结束单独上岛：左右翼用紧凑宽；与 B/专注并排时仍跟标准翼宽。
    var usesDualFlushCompactWings: Bool {
        guard case .fullNotice(let payload) = resolvedLayout else { return false }
        switch payload {
        case .ramPressure, .processEnded:
            return true
        default:
            return false
        }
    }

    var dualFlushWingWidth: CGFloat {
        usesDualFlushCompactWings
            ? IslandChrome.dualFlushCompactWingWidth
            : IslandChrome.dualFlushLeftWingWidth
    }

    var anyUsesNotchRightOrbChrome: Bool {
        // 「已复制」单独时用圆岛；与 B/专注并排时走翼宽，圆岛画在右翼即可。
        if focusResident || mediaResident || downloadResident { return false }
        if primary != nil { return false }
        return secondary?.usesNotchRightOrbChrome == true
    }

    var isDual: Bool {
        if case .dual = resolvedLayout { return true }
        return false
    }

    var resolvedLayout: IslandNoticeLayout {
        IslandNoticeSlotPolicy.resolvedLayout(self)
    }
}

/// 双槽投递 / 撤回 / 布局纯函数。
enum IslandNoticeSlotPolicy {
    static func applying(
        incoming: IslandNoticePayload,
        to slots: IslandNoticeSlots
    ) -> IslandNoticeSlots? {
        let lane = incoming.displayLane

        if lane == .exclusive {
            var next = slots
            next.primary = incoming
            next.secondary = nil
            next.secondaryQueue = []
            return next
        }

        if slots.primary?.displayLane == .exclusive {
            return nil
        }

        switch lane {
        case .exclusive:
            return nil

        case .primary:
            if let existing = slots.primary,
               existing.id != incoming.id,
               existing.displayLane == .primary,
               incoming.preemptionRank < existing.preemptionRank
            {
                return nil
            }
            var next = slots
            next.primary = incoming
            return next

        case .secondary:
            return applySecondary(incoming, to: slots)
        }
    }

    /// D：同时只展示一条；已有可见 D 时按出现顺序入队。
    private static func applySecondary(
        _ incoming: IslandNoticePayload,
        to slots: IslandNoticeSlots
    ) -> IslandNoticeSlots? {
        var next = slots
        if let existing = slots.secondary {
            if existing.id == incoming.id {
                next.secondary = incoming
                return next
            }
            if let idx = next.secondaryQueue.firstIndex(where: { $0.id == incoming.id }) {
                next.secondaryQueue[idx] = incoming
            } else {
                next.secondaryQueue.append(incoming)
            }
            return next
        }
        next.secondary = incoming
        return next
    }

    static func dismissing(id: String?, from slots: IslandNoticeSlots) -> IslandNoticeSlots {
        guard let id else {
            return IslandNoticeSlots(
                focusResident: slots.focusResident,
                mediaResident: slots.mediaResident,
                downloadResident: slots.downloadResident
            )
        }
        var next = slots
        if next.primary?.id == id {
            next.primary = nil
        }
        if next.secondary?.id == id {
            if next.secondaryQueue.isEmpty {
                next.secondary = nil
            } else {
                next.secondary = next.secondaryQueue.removeFirst()
            }
        } else {
            next.secondaryQueue.removeAll { $0.id == id }
        }
        return next
    }

    static func withFocusResident(_ enabled: Bool, slots: IslandNoticeSlots) -> IslandNoticeSlots {
        var next = slots
        next.focusResident = enabled
        return next
    }

    static func withMediaResident(_ enabled: Bool, slots: IslandNoticeSlots) -> IslandNoticeSlots {
        var next = slots
        next.mediaResident = enabled
        return next
    }

    static func withDownloadResident(_ enabled: Bool, slots: IslandNoticeSlots) -> IslandNoticeSlots {
        var next = slots
        next.downloadResident = enabled
        return next
    }

    /// 布局解析（产品 A > B > C > D；C 内下载 > 计时）。
    /// 契约在 `LockedInvariants.LayoutMatrix`（未授权禁改）。
    static func resolvedLayout(_ slots: IslandNoticeSlots) -> IslandNoticeLayout {
        LockedInvariants.LayoutMatrix.resolvedLayout(slots)
    }
}

extension IslandNoticePayload {
    var displayLane: IslandNoticeDisplayLane {
        switch self {
        case .colorPickTip, .ocrSelectTip:
            return .exclusive
        case .meetingLead:
            return .primary
        case .clipboardCaptureHint, .moveReminder, .processEnded,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged,
             .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected,
             .systemFocusOn, .systemFocusOff,
             .aiUsageAlert, .ramPressure:
            // D（含系统专注 tip）：靠右半块 / 单独满岛；多条 FIFO。与 C 计时无关。
            return .secondary
        }
    }
}
