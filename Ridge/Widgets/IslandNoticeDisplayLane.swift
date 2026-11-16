import Foundation

/// 提示三档。
///
/// - exclusive (A)：框选 / 取色 → 满岛
/// - primary (B)：**会议 tip / 音乐常驻** → 两 B 同时只展示会议（盖音乐）；与短 C 并排时左会议右 C；C 没后会议回满岛
/// - secondary (C)：复制 / 久坐 / 外设 / 额度等；「已复制」圆岛本就靠右，满不满无所谓
///
/// 专注计时收起待命是 **C 常驻**：
/// - 仅它 → 满岛；+短 C → 左专注右短条；+B → 左 B 右专注
/// - 右翼是专注时来短 C → 短 C 暂占约 2–3s，没后专注归位
///
/// 凡 `.dual`（含会议+C、音乐+C）一律 **dualFlush** 左右小岛，禁止再抬会议双翼宽。
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
    /// 当前可见的 C 短条。
    var secondary: IslandNoticePayload?
    /// 被短 C 暂时挤走的粘性 C（如久坐）。
    var parkedSecondary: IslandNoticePayload?
    /// 专注计时收起待命（C 常驻）。
    var focusResident: Bool = false
    /// 音乐播放小岛（B；无会议时生效，会议盖音乐）。
    var mediaResident: Bool = false

    var current: IslandNoticePayload? { primary ?? secondary }

    var isEmpty: Bool {
        primary == nil && secondary == nil && parkedSecondary == nil
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
        [primary?.id, secondary?.id, parkedSecondary?.id].compactMap { $0 }
    }

    func contains(id: String) -> Bool {
        primary?.id == id || secondary?.id == id || parkedSecondary?.id == id
    }

    var anyKeepsExpandedWithoutHover: Bool {
        (primary?.keepsExpandedWithoutHover == true)
            || (secondary?.keepsExpandedWithoutHover == true)
            || (parkedSecondary?.keepsExpandedWithoutHover == true)
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

    /// 任意 `.dual` 都走贴刘海左右 flush（音乐标准）；含会议+C、两 B 后再出 C。
    var usesDualFlushChrome: Bool {
        if case .dual = resolvedLayout { return true }
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
            next.parkedSecondary = nil
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

    private static func applySecondary(
        _ incoming: IslandNoticePayload,
        to slots: IslandNoticeSlots
    ) -> IslandNoticeSlots? {
        var next = slots
        if let existing = slots.secondary, existing.id != incoming.id {
            let existingSticky = existing.autoDismissNanoseconds == nil
            let incomingEphemeral = incoming.autoDismissNanoseconds != nil
            if existingSticky, incomingEphemeral {
                next.parkedSecondary = existing
                next.secondary = incoming
                return next
            }
            if existingSticky,
               incoming.autoDismissNanoseconds == nil,
               incoming.preemptionRank < existing.preemptionRank
            {
                return nil
            }
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
            next.secondary = next.parkedSecondary
            next.parkedSecondary = nil
        }
        if next.parkedSecondary?.id == id {
            next.parkedSecondary = nil
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
    /// 会议满岛时来短 C → 左会议右 C（音乐仍被盖）；C 没后会议回满岛。
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

        // 无 B：仅 C 族
        if let secondary = slots.secondary {
            if slots.focusResident {
                return .dual(left: .focus, right: .notice(secondary))
            }
            // 单独「已复制」：圆岛靠右，满不满无所谓
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
        case .meetingLead, .ramPressure:
            return .primary
        case .clipboardCaptureHint, .moveReminder, .processEnded,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .aiUsageAlert:
            return .secondary
        }
    }
}
