import Foundation

/// 提示三档与展示权重（高 → 低）：
///
/// 1. **取色 / 框选 / 会议**（最高）
/// 2. **播放**
/// 3. **专注**
/// 4. **C 类短提示**（复制 / 久坐 / 外设 / 额度 / RAM / 进程结束…）
///
/// 形态：
/// - 取色 / 框选 → 满岛独占（清 C 队列）
/// - 会议 + 播放 → **会议满岛**（盖音乐）
/// - 左会议或音乐 + 右 C 或专注
/// - 左专注 + 右 C（无会议/音乐时）
/// - 专注已在右翼时来了 C → C **先盖住**专注；C 约 3s 收起后专注回到右翼
///
/// 多条非专注 C：**FIFO**，同时只一条。
/// 凡 `.dual` 一律 **dualFlush** 左右小岛，禁止再抬会议双翼宽。
///
/// - exclusive (A)：取色 / 框选
/// - primary (B)：会议 tip（音乐常驻走 `mediaResident`）
/// - secondary (C)：短提示
enum IslandNoticeDisplayLane: Int, Equatable, Comparable {
    case secondary = 0
    case primary = 1
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
    case dual(left: IslandNoticeLayoutSide, right: IslandNoticeLayoutSide)
}

enum IslandNoticeLayoutSide: Equatable {
    case notice(IslandNoticePayload)
    case focus
    case media
}

/// 主 / 次 / 常驻旗标快照。
struct IslandNoticeSlots: Equatable {
    /// A 或 B 通知（会议等）；音乐不走 payload，见 `mediaResident`。
    var primary: IslandNoticePayload?
    /// 当前可见的 C 短条（非专注；靠右或单独满岛）。
    var secondary: IslandNoticePayload?
    /// 等待中的 C（FIFO；出现顺序）。
    var secondaryQueue: [IslandNoticePayload] = []
    /// 专注计时中（权重低于播放；有播放时居右，被 C 暂盖后会回到右翼）。
    var focusResident: Bool = false
    /// 音乐播放中（权重低于会议；会议在时满岛会议盖住音乐）。
    var mediaResident: Bool = false

    var current: IslandNoticePayload? { primary ?? secondary }

    var isEmpty: Bool {
        primary == nil && secondary == nil && secondaryQueue.isEmpty
            && !focusResident && !mediaResident
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
        case .fullFocus, .fullMedia, .dual, .empty:
            // 双槽一律左右 flush 小岛，勿抬会议双翼宽；单独专注/音乐不走翼 tip。
            return false
        case .fullNotice(let p):
            // 仅「满岛单 tip」（如只有会议 / 两 B 时只留会议）才用双翼壳。
            return p.usesNotchWingChrome
        }
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
        if focusResident || mediaResident { return false }
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

    /// 非专注 C：同时只展示一条；已有可见 C 时按出现顺序入队。
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
                mediaResident: slots.mediaResident
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

    /// 布局解析（权重：取色/框选/会议 > 播放 > 专注 > C）。
    /// 会议盖播放满岛；左=会议|音乐|专注，右=C|专注；C 暂盖右翼专注，撤后专注回右。
    static func resolvedLayout(_ slots: IslandNoticeSlots) -> IslandNoticeLayout {
        if let primary = slots.primary, primary.displayLane == .exclusive {
            return .fullNotice(primary)
        }

        // B：会议 tip（可与 mediaResident 并存；布局层始终盖音乐）
        if let primary = slots.primary {
            if let secondary = slots.secondary {
                // 两 B + C，或会议 + C → 左会议右 C；勿再把音乐摆上右/左翼
                return .dual(left: .notice(primary), right: .notice(secondary))
            }
            if slots.focusResident {
                return .dual(left: .notice(primary), right: .focus)
            }
            // 仅会议，或会议+音乐两 B：只展示加入会议满岛 tip
            return .fullNotice(primary)
        }

        // B：音乐（无会议时才生效）
        if slots.mediaResident {
            if let secondary = slots.secondary {
                // 短 C 占右；专注与 C 同时时专注让路。
                return .dual(left: .media, right: .notice(secondary))
            }
            if slots.focusResident {
                return .dual(left: .media, right: .focus)
            }
            return .fullMedia
        }

        // 无 B：专注左 + 短 C 右；或单独短 C 满岛；或仅专注
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

extension IslandNoticePayload {
    var displayLane: IslandNoticeDisplayLane {
        switch self {
        case .colorPickTip, .ocrSelectTip:
            return .exclusive
        case .meetingLead:
            return .primary
        case .clipboardCaptureHint, .moveReminder, .processEnded,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .aiUsageAlert, .ramPressure:
            // 非专注 C：靠右半块 / 单独满岛；多条 FIFO。
            return .secondary
        }
    }
}
