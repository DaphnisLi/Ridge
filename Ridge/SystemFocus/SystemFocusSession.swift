import Combine
import Darwin
import Foundation

/// 系统 Focus / 勿扰监测：开·关·切换 → 瞬时 tip；需完全磁盘访问读名称/图标/结束时间。
@MainActor
final class SystemFocusSession: ObservableObject {
    static let shared = SystemFocusSession()

    @Published private(set) var latest: SystemFocusSnapshot = .unread
    @Published private(set) var canReadStore = false

    private var started = false
    private var seeded = false
    private var pollTimer: Timer?
    private var assertionsSource: DispatchSourceFileSystemObject?
    private var modesSource: DispatchSourceFileSystemObject?
    private var assertionsFD: Int32 = -1
    private var modesFD: Int32 = -1
    /// 关闭 tip 仍展示刚关掉的模式名 / 图标。
    private var lastKnownMode: SystemFocusModeInfo?

    private init() {}

    private var tipEnabled: Bool {
        WidgetSettings.shared.isEnabled(SystemFocusTipWidget.manifest.id)
    }

    func start() {
        guard !started else {
            AppLog.debug("SystemFocus", "会话已在跑，跳过重复 start")
            return
        }
        started = true
        refresh(reason: "start")
        startFileWatches()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "poll")
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        AppLog.warn("SystemFocus", "系统 Focus tip 会话已启动", [
            "tipOn": tipEnabled,
            "canRead": canReadStore,
            "active": latest.isActive,
            "mode": latest.mode?.name ?? ""
        ])
    }

    func stop() {
        guard started else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        stopFileWatches()
        started = false
        seeded = false
        AppLog.warn("SystemFocus", "系统 Focus tip 会话已停止")
    }

    func refresh(reason: String) {
        let snap = SystemFocusStoreReader.readSnapshot()
        apply(snap, reason: reason)
    }

    /// 设置页「打开完全磁盘访问」后立刻再探。
    func recheckAccess(reason: String) {
        refresh(reason: reason)
    }

    // MARK: - Apply

    private func apply(_ snap: SystemFocusSnapshot, reason: String) {
        let previous = latest
        canReadStore = snap.canReadStore
        if let mode = snap.mode {
            lastKnownMode = mode
        }

        let changed = snap.isActive != previous.isActive
            || snap.mode?.modeIdentifier != previous.mode?.modeIdentifier
            || snap.endsAt != previous.endsAt
            || snap.canReadStore != previous.canReadStore

        latest = snap

        if !seeded {
            seeded = true
            AppLog.warn("SystemFocus", "Focus 状态已播种", [
                "reason": reason,
                "canRead": snap.canReadStore,
                "active": snap.isActive,
                "mode": snap.mode?.name ?? "",
                "endsAt": snap.endsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "tipOn": tipEnabled
            ])
            return
        }

        guard changed else { return }

        AppLog.warn("SystemFocus", "Focus 状态变化", [
            "reason": reason,
            "canRead": snap.canReadStore,
            "active": snap.isActive,
            "mode": snap.mode?.name ?? lastKnownMode?.name ?? "",
            "endsAt": snap.endsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "tipOn": tipEnabled
        ])

        guard tipEnabled, snap.canReadStore else { return }

        if snap.isActive {
            presentOn(snap: snap, reason: reason)
        } else if previous.isActive {
            presentOff(reason: reason)
        }
    }

    private func presentOn(snap: SystemFocusSnapshot, reason: String) {
        let mode = snap.mode ?? lastKnownMode ?? SystemFocusModeInfo(
            modeIdentifier: "unknown",
            name: L10n.SystemFocus.fallbackGeneric,
            symbolImageName: "moon.fill",
            tintColorName: "systemIndigoColor"
        )
        let detail: String
        if let endsAt = snap.endsAt {
            detail = L10n.SystemFocus.untilTime(Self.timeString(endsAt))
        } else {
            detail = L10n.SystemFocus.openedBadge
        }
        let notice = SystemFocusNotice(
            id: "systemFocus.on.\(UUID().uuidString.prefix(8))",
            kind: .on,
            name: mode.name,
            symbolImageName: mode.symbolImageName,
            tintColorName: mode.tintColorName,
            detail: detail,
            endsAt: snap.endsAt
        )
        IslandNoticeCenter.shared.present(.systemFocusOn(notice))
        AppLog.warn("SystemFocus", "已投递 Focus 开启 tip", [
            "reason": reason,
            "name": mode.name,
            "symbol": mode.symbolImageName,
            "detail": detail
        ])
    }

    private func presentOff(reason: String) {
        let mode = lastKnownMode ?? SystemFocusModeInfo(
            modeIdentifier: "unknown",
            name: L10n.SystemFocus.fallbackDoNotDisturb,
            symbolImageName: "moon.fill",
            tintColorName: "systemIndigoColor"
        )
        let notice = SystemFocusNotice(
            id: "systemFocus.off.\(UUID().uuidString.prefix(8))",
            kind: .off,
            name: mode.name,
            symbolImageName: mode.symbolImageName,
            tintColorName: mode.tintColorName,
            detail: L10n.SystemFocus.closedBadge,
            endsAt: nil
        )
        IslandNoticeCenter.shared.present(.systemFocusOff(notice))
        AppLog.warn("SystemFocus", "已投递 Focus 关闭 tip", [
            "reason": reason,
            "name": mode.name,
            "symbol": mode.symbolImageName
        ])
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - File watch

    private func startFileWatches() {
        stopFileWatches()
        assertionsFD = openWatch(SystemFocusStoreReader.assertionsURL, assign: { [weak self] src in
            self?.assertionsSource = src
        })
        modesFD = openWatch(SystemFocusStoreReader.modeConfigurationsURL, assign: { [weak self] src in
            self?.modesSource = src
        })
    }

    private func stopFileWatches() {
        assertionsSource?.cancel()
        modesSource?.cancel()
        assertionsSource = nil
        modesSource = nil
        if assertionsFD >= 0 { close(assertionsFD); assertionsFD = -1 }
        if modesFD >= 0 { close(modesFD); modesFD = -1 }
    }

    @discardableResult
    private func openWatch(
        _ url: URL,
        assign: (DispatchSourceFileSystemObject) -> Void
    ) -> Int32 {
        let path = url.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            AppLog.debug("SystemFocus", "无法监视 Focus 文件（可能缺完全磁盘访问）", [
                "file": url.lastPathComponent
            ])
            return -1
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.refresh(reason: "fs:\(url.lastPathComponent)")
                // rename/replace 后需重挂监视。
                self?.startFileWatches()
            }
        }
        // fd 由 stopFileWatches 统一 close，避免与 cancel 双关。
        assign(source)
        source.resume()
        return fd
    }

    // MARK: - Samples（设置 / 测试台）

    func presentSample(kind: SystemFocusTipKind) {
        let notice: SystemFocusNotice
        switch kind {
        case .on:
            notice = SystemFocusNoticeCard.previewNotice(kind: .on)
        case .off:
            notice = SystemFocusNoticeCard.previewNotice(kind: .off)
        }
        let live = SystemFocusNotice(
            id: "test.systemFocus.\(kind.rawValue).\(UUID().uuidString.prefix(6))",
            kind: notice.kind,
            name: notice.name,
            symbolImageName: notice.symbolImageName,
            tintColorName: notice.tintColorName,
            detail: notice.detail,
            endsAt: notice.endsAt
        )
        switch kind {
        case .on: IslandNoticeCenter.shared.present(.systemFocusOn(live))
        case .off: IslandNoticeCenter.shared.present(.systemFocusOff(live))
        }
        AppLog.info("SystemFocus", "已投递 Focus 样张 tip", ["kind": kind.rawValue])
    }
}
