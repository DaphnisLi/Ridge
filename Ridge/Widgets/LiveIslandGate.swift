import Foundation

/// 实况类（`WidgetLibraryFamily.live`）上岛闸门：有状态时直接准入分页（不再投「打开」邀请 tip）。
@MainActor
final class LiveIslandGate: ObservableObject {
    static let shared = LiveIslandGate()

    static let mediaID: WidgetID = "builtin.media"
    static let batteryID: WidgetID = "system.controlDeck.battery"

    /// 当前允许常驻上岛的实况 id（有曲目 / 有外设时自动 admit）。
    @Published private(set) var openedIDs: Set<WidgetID> = []

    private init() {}

    func isOpened(_ id: WidgetID) -> Bool {
        openedIDs.contains(id)
    }

    nonisolated static func inviteNoticeID(for widgetID: WidgetID) -> String {
        "live.invite.\(widgetID)"
    }

    /// 有内容时直接准入分页，并清掉遗留的实况邀请 tip（产品已去掉邀请条）。
    func admit(_ id: WidgetID, reason: String) {
        guard WidgetLibraryFamily.family(for: id) == .live else {
            AppLog.warn("LiveGate", "admit 跳过：非实况组件", ["id": id, "reason": reason])
            return
        }
        IslandNoticeCenter.shared.dismiss(id: Self.inviteNoticeID(for: id))
        let inserted = openedIDs.insert(id).inserted
        guard inserted else { return }
        WidgetRuntime.shared.recompute(reason: "liveAdmit:\(reason)")
        AppLog.info("LiveGate", "实况已自动准入", [
            "id": id,
            "reason": reason
        ])
    }

    /// 点低电等瞬时条进入实况面板：登记 → 切页并展开。
    func open(_ id: WidgetID, reason: String) {
        guard WidgetLibraryFamily.family(for: id) == .live else {
            AppLog.warn("LiveGate", "open 跳过：非实况组件", ["id": id, "reason": reason])
            return
        }
        let inserted = openedIDs.insert(id).inserted
        IslandNoticeCenter.shared.dismiss(id: Self.inviteNoticeID(for: id))

        switch id {
        case Self.batteryID:
            ControlDeckSettings.shared.activePane = .battery
            WidgetRuntime.shared.focusControlDeck(pane: .battery)
        case Self.mediaID:
            WidgetRuntime.shared.revealPage(id, reason: "liveOpen:\(reason)", remember: false)
        default:
            WidgetRuntime.shared.revealPage(id, reason: "liveOpen:\(reason)", remember: true)
        }

        IslandController.shared?.expand(reason: "liveOpen:\(id)")
        AppLog.info("LiveGate", "实况已点进面板", [
            "id": id,
            "reason": reason,
            "new": inserted
        ])
    }

    /// 内容消失 / 模块关闭：撤常驻资格，并触发分页重算。
    func close(_ id: WidgetID, reason: String) {
        guard openedIDs.remove(id) != nil else { return }
        IslandNoticeCenter.shared.dismiss(id: Self.inviteNoticeID(for: id))
        if ControlDeckSettings.isControlDeckPageID(id) {
            WidgetRuntime.shared.recompute(reason: "liveClose:\(reason)")
        }
        AppLog.info("LiveGate", "实况已撤出常驻", ["id": id, "reason": reason])
    }

    func closeAll(reason: String) {
        let ids = openedIDs
        guard !ids.isEmpty else { return }
        openedIDs.removeAll()
        for id in ids {
            IslandNoticeCenter.shared.dismiss(id: Self.inviteNoticeID(for: id))
        }
        WidgetRuntime.shared.recompute(reason: "liveCloseAll:\(reason)")
        AppLog.info("LiveGate", "已清空全部实况常驻", [
            "reason": reason,
            "count": ids.count
        ])
    }
}

/// 实况「点进面板」邀请提示载荷。
struct LiveIslandInvite: Hashable {
    let widgetID: WidgetID
    let title: String
    let subtitle: String
    let symbol: String

    var noticeID: String {
        LiveIslandGate.inviteNoticeID(for: widgetID)
    }
}
