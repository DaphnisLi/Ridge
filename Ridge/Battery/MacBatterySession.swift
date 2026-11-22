import Combine
import Foundation
import IOKit.ps

/// 本机电池监测：插电 / 满电 / 低电 / 拔电 → `IslandNoticeCenter`；无内置电池则静默。
@MainActor
final class MacBatterySession: ObservableObject {
    static let shared = MacBatterySession()

    @Published private(set) var latest: MacBatteryProbe.Snapshot?
    @Published private(set) var hasInternalBattery = false

    private let settings = MacBatterySettings.shared
    private var timer: Timer?
    private var powerSourceSource: CFRunLoopSource?
    private var started = false

    /// 低电已提示过，电量回升后再武装。
    private var lowArmed = false
    /// 充满已提示过，拔电后再武装。
    private var fullArmed = false
    /// 上一拍是否接电（AC / 正在充）；用于边沿检测插电 / 拔电。
    private var wasOnAC = false
    /// 首轮只播种状态，不弹 tip。
    private var seeded = false

    private init() {}

    private var tipEnabled: Bool {
        WidgetSettings.shared.isEnabled(MacBatteryTipWidget.manifest.id)
    }

    func start() {
        guard !started else {
            refresh(reason: "resume")
            return
        }
        started = true
        installPowerSourceObserver()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "tick")
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refresh(reason: "start")
        AppLog.warn("MacBattery", "本机电池会话已启动", [
            "hasBattery": hasInternalBattery,
            "tipOn": tipEnabled,
            "percent": latest?.percent ?? -1,
            "onAC": latest?.isOnAC ?? false,
            "charging": latest?.isCharging ?? false,
            "power": latest?.powerState ?? ""
        ])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let powerSourceSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceSource, .commonModes)
            self.powerSourceSource = nil
        }
        started = false
        AppLog.warn("MacBattery", "本机电池会话已停止")
    }

    func refresh(reason: String) {
        let snap = MacBatteryProbe.snapshot()
        hasInternalBattery = snap != nil
        latest = snap

        guard let snap else {
            if seeded {
                AppLog.debug("MacBattery", "无内置电池，跳过 tip", ["reason": reason])
            }
            seeded = true
            wasOnAC = false
            return
        }

        evaluate(snap, reason: reason)
    }

    private func evaluate(_ snap: MacBatteryProbe.Snapshot, reason: String) {
        let tipOn = tipEnabled
        let threshold = settings.lowThresholdPercent

        if !seeded {
            seeded = true
            wasOnAC = snap.isOnAC
            if snap.percent <= threshold { lowArmed = true }
            if snap.isCharged || (snap.isOnAC && snap.percent >= 100) { fullArmed = true }
            AppLog.warn("MacBattery", "本机电池已播种", [
                "reason": reason,
                "percent": snap.percent,
                "onAC": snap.isOnAC,
                "charging": snap.isCharging,
                "charged": snap.isCharged,
                "power": snap.powerState,
                "tipOn": tipOn
            ])
            return
        }

        if snap.percent > threshold + 5 {
            lowArmed = false
        }
        if !snap.isOnAC {
            fullArmed = false
        }

        guard tipOn else {
            wasOnAC = snap.isOnAC
            return
        }

        // 四态均随小组件总开关；无分项开关。

        // 1 插电：电池 → AC（含优化充电「已接电未在充」）。
        if !wasOnAC,
           snap.isOnAC,
           !snap.isCharged,
           snap.percent < 100
        {
            present(
                kind: .charging,
                percent: snap.percent,
                threshold: 0,
                detail: L10n.MacBattery.chargingDetail
            )
        }

        // 2 满电：接电且满电 / isCharged。
        if snap.isOnAC,
           (snap.isCharged || snap.percent >= 100),
           !fullArmed
        {
            fullArmed = true
            present(
                kind: .full,
                percent: max(snap.percent, 100),
                threshold: 100,
                detail: L10n.MacBattery.fullDetail
            )
        }

        // 3 低电：未接电且 ≤ 阈值。
        if !snap.isOnAC,
           snap.percent <= threshold,
           !lowArmed
        {
            lowArmed = true
            present(
                kind: .low,
                percent: snap.percent,
                threshold: threshold,
                detail: L10n.MacBattery.lowDetail(snap.percent, threshold)
            )
        }

        // 4 拔电：AC → 电池；若同时触低电，低电由上支路另投（FIFO）。
        if wasOnAC,
           !snap.isOnAC
        {
            present(
                kind: .unplugged,
                percent: snap.percent,
                threshold: 0,
                detail: L10n.MacBattery.unplugDetail
            )
        }

        wasOnAC = snap.isOnAC
    }

    private func present(kind: MacBatteryNotice.Kind, percent: Int, threshold: Int, detail: String) {
        let notice = MacBatteryNotice(
            id: "macBattery.\(kind.rawValue).\(percent).\(UUID().uuidString.prefix(6))",
            kind: kind,
            percent: percent,
            threshold: threshold,
            detail: detail
        )
        let payload: IslandNoticePayload
        switch kind {
        case .charging: payload = .macBatteryCharging(notice)
        case .full: payload = .macBatteryFull(notice)
        case .low: payload = .macBatteryLow(notice)
        case .unplugged: payload = .macBatteryUnplugged(notice)
        }
        IslandNoticeCenter.shared.present(payload)
        AppLog.warn("MacBattery", "已投递本机电池 tip", [
            "kind": kind.rawValue,
            "percent": percent,
            "threshold": threshold,
            "onAC": latest?.isOnAC ?? false,
            "charging": latest?.isCharging ?? false
        ])
    }

    /// 设置页 / 测试台：直接投递样张，不改真实武装态。
    func presentSample(kind: MacBatteryNotice.Kind) {
        let threshold = settings.lowThresholdPercent
        let percent: Int
        let detail: String
        switch kind {
        case .charging:
            percent = latest?.percent ?? 78
            detail = L10n.MacBattery.chargingDetail
        case .full:
            percent = 100
            detail = L10n.MacBattery.fullDetail
        case .low:
            percent = max(1, threshold - 3)
            detail = L10n.MacBattery.lowDetail(percent, threshold)
        case .unplugged:
            percent = latest?.percent ?? 64
            detail = L10n.MacBattery.unplugDetail
        }
        let tipThreshold: Int
        switch kind {
        case .low: tipThreshold = threshold
        case .full: tipThreshold = 100
        case .charging, .unplugged: tipThreshold = 0
        }
        present(kind: kind, percent: percent, threshold: tipThreshold, detail: detail)
        AppLog.warn("MacBattery", "已投递本机电池样张", ["kind": kind.rawValue])
    }

    private func installPowerSourceObserver() {
        guard powerSourceSource == nil else { return }
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in
                MacBatterySession.shared.refresh(reason: "powerSourceChange")
            }
        }, nil) else {
            AppLog.warn("MacBattery", "无法注册电源变化通知，仅靠定时轮询")
            return
        }
        let source = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceSource = source
        AppLog.warn("MacBattery", "已注册电源变化通知")
    }
}
