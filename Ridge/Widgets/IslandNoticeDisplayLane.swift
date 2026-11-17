import Foundation

/// 提示三档。
///
/// - exclusive (A)：框选 / 取色 → 满岛
/// - primary (B)：**会议 tip / 音乐常驻** → 两 B 同时只展示会议（盖音乐）；与短 C 并排时左会议右 C；C 没后会议回满岛
/// - secondary (C)：复制 / 久坐 / 外设 / 额度 / RAM 等（**除专注外一律靠右**）
///
/// 专注计时收起待命是 **C 常驻**（左翼优先于短 C）：
/// - 仅它 → 满岛；+短 C → 左专注右短条；+B → 左 B 右专注
///
/// 多条非专注 C：**FIFO 队列**，同时只展示一条；前一条 3s 收起后出下一条。
/// 凡 `.dual`（含会议+C、音乐+C、专注+C）一律 **dualFlush** 左右小岛，禁止再抬会议双翼宽。
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
    /// 专注计时收起待命（C 常驻，布局上居左优先）。
    var focusResident: Bool = false
    /// 音乐播放小岛（B；无会议时生效，会议盖音乐）。
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

    /// 任意 `.dual` 都走贴刘海左右 flush；单独 RAM 高压也走 dualFlush 右半块。
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

    /// 单独 RAM 高压：只要右翼半块（C 靠右），勿再铺左翼黑底。
    var usesDualFlushTrailingOnly: Bool {
        guard case .fullNotice(let payload) = resolvedLayout else { return false }
        return payload.usesDualFlushSoloChrome
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

    /// 布局解析。
    /// B = 会议 tip（primary）或音乐常驻；两 B 同时只展示会议（盖音乐）。
    /// 非专注 C 靠右；专注常驻居左（仅它 / 对 B 居右 / 对短 C 居左）。
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
                return .dual(left: .media, right: .notice(secondary))
            }
            if slots.focusResident {
                // 专注与音乐互斥于业务层；若同时亮旗，专注优先占满。
                return .fullFocus
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
