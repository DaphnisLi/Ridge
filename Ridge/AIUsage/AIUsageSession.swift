import Combine
import Foundation

/// AI 额度会话：定时刷新 Cursor。
/// 提示规则：
/// - 平时：同账号同周期内，显示剩余**跌破**某条线（充裕 / 警戒 / 截流）时弹对应形态一次；
/// - 换账号 / 新计费周期：作用域切换，按新身份重新判定（已在触发带则弹）；
/// - 改阈值：按新线立刻重判，若当前已在某档内则强制再弹该档。
@MainActor
final class AIUsageSession: ObservableObject {
    static let shared = AIUsageSession()

    @Published private(set) var snapshot: AIUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let settings = AIUsageSettings.shared
    private var timer: Timer?
    private var started = false
    private var settingsObservers: Set<AnyCancellable> = []
    private var thresholdChangeTask: Task<Void, Never>?
    /// 上次采样的显示剩余；用于判断是否「跌破」某条线。
    private var lastSampledPercent: Int?
    /// 上次采样的账号+周期；切换时边沿基准作废。
    private var lastSampledScope: AIUsageAlertScope?
    /// 串行刷新：避免改阈值与定时刷新互相 `isRefreshing` 跳过。
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        // 仅感知开关 / 刷新间隔影响定时器；阈值变更不走这里（否则拖滑条狂刷 timer）。
        settings.$sensingEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluateSensing(reason: "sensing")
            }
            .store(in: &settingsObservers)
        settings.$refreshMinutes
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluateSensing(reason: "refreshMinutes")
            }
            .store(in: &settingsObservers)
    }

    func start() {
        guard !started else { return }
        started = true
        AppLog.warn("AIUsage", "会话启动", ["sensing": settings.sensingEnabled])
        reevaluateSensing(reason: "start")
        Task { await refresh(reason: "start", evaluateTips: true) }
    }

    /// 用户改阈值：防抖后清去重 → 拉数 → 若已在触发带内强制弹一档。
    func thresholdsDidChange(reason: String) {
        thresholdChangeTask?.cancel()
        thresholdChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled, let self else { return }
            AppLog.warn("AIUsage", "阈值已变更，强制按新线重判", [
                "reason": reason,
                "abundantAt": self.settings.abundantThreshold,
                "warningAt": self.settings.warningThreshold,
                "criticalAt": self.settings.criticalThreshold,
                "cachedRemaining": self.snapshot?.cursor?.remainingPercent.map {
                    self.settings.displayRemainingPercent($0)
                } ?? -1
            ])
            self.settings.clearAlertMemory()
            self.lastSampledPercent = nil
            self.lastSampledScope = nil
            // 等在途刷新结束再拉，避免 isRefreshing 直接跳过。
            await self.refresh(reason: "thresholdChange:\(reason)", evaluateTips: false)
            guard !Task.isCancelled else { return }
            self.maybePresentThresholdNotice(forceIfInBand: true)
        }
    }

    /// - Parameter evaluateTips: 是否在刷新后走边沿提示；改阈值路径为 false，随后单独 force。
    func refresh(reason: String, evaluateTips: Bool = true) async {
        if isRefreshing {
            AppLog.warn("AIUsage", "刷新进行中，排队等待", ["reason": reason])
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                refreshWaiters.append(cont)
            }
            // 等完后若仍是改阈值，继续往下再刷一枪拿最新线；其它原因可直接复用刚刷完的结果。
            if !reason.hasPrefix("thresholdChange") {
                if evaluateTips {
                    maybePresentThresholdNotice(forceIfInBand: false)
                }
                return
            }
        }

        isRefreshing = true
        AppLog.warn("AIUsage", "开始刷新用量", ["reason": reason])

        let previousGood = snapshot?.cursor.flatMap { $0.errorMessage == nil ? $0 : nil }
        let fromThresholdEdit = reason.hasPrefix("thresholdChange")

        do {
            let cursor = try await CursorUsageClient.fetchSnapshot()
            lastError = nil
            snapshot = AIUsageSnapshot(providers: [cursor], updatedAt: Date())
        } catch {
            let message = Self.userMessage(for: error)
            lastError = message
            let isCancel = (error as NSError).code == NSURLErrorCancelled
                || (error as? URLError)?.code == .cancelled
            if let previousGood, fromThresholdEdit || isCancel {
                AppLog.warn("AIUsage", "刷新失败，保留上次有效用量", [
                    "reason": reason,
                    "message": message,
                    "cancelled": isCancel
                ])
            } else {
                snapshot = AIUsageSnapshot(
                    providers: [
                        AIUsageProviderSnapshot(
                            id: .cursor,
                            planLabel: nil,
                            accountHint: nil,
                            accountID: nil,
                            windows: [],
                            onDemand: nil,
                            fetchedAt: Date(),
                            errorMessage: message,
                            isStale: true
                        )
                    ],
                    updatedAt: Date()
                )
                AppLog.warn("AIUsage", "Cursor 刷新失败", ["reason": reason, "message": message])
            }
        }

        isRefreshing = false
        let waiters = refreshWaiters
        refreshWaiters = []
        for waiter in waiters { waiter.resume() }

        if evaluateTips {
            maybePresentThresholdNotice(forceIfInBand: false)
        }
    }

    private func reevaluateSensing(reason: String) {
        timer?.invalidate()
        timer = nil
        guard settings.sensingEnabled else {
            AppLog.info("AIUsage", "感知已关闭", ["reason": reason])
            return
        }
        let minutes = max(settings.refreshMinutes, 1)
        let timer = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(reason: "timer", evaluateTips: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        AppLog.warn("AIUsage", "已安排定时刷新", ["minutes": minutes, "reason": reason])
    }

    /// - Parameter forceIfInBand: 改阈值后：只要当前显示剩余落在某档，就弹该档（忽略同档锁）。
    private func maybePresentThresholdNotice(forceIfInBand: Bool) {
        guard settings.sensingEnabled else {
            AppLog.warn("AIUsage", "跳过额度提示：感知已关闭")
            return
        }
        guard let cursor = snapshot?.cursor,
              cursor.errorMessage == nil,
              let remaining = cursor.remainingPercent
        else {
            AppLog.warn("AIUsage", "跳过额度提示：无有效剩余", [
                "error": snapshot?.cursor?.errorMessage ?? "nil"
            ])
            return
        }

        let scope = cursor.alertScope
        let percent = settings.displayRemainingPercent(remaining)
        let tipStage = settings.tipStage(forRemaining: remaining)
        let scopeChanged = lastSampledScope.map { $0 != scope } ?? false
        // 作用域变了则边沿基准作废（不能拿旧账号的剩余去算穿越）。
        let previous = scopeChanged ? nil : lastSampledPercent
        defer {
            lastSampledPercent = percent
            lastSampledScope = scope
        }

        guard let tipStage else {
            if settings.lastAlertedStage(for: scope)?.1 != .unknown {
                settings.rememberAlert(provider: .cursor, stage: .unknown, scope: scope)
            }
            AppLog.warn("AIUsage", "跳过额度提示：未触达任一触发线", [
                "remaining": percent,
                "abundantAt": settings.abundantThreshold,
                "warningAt": settings.warningThreshold,
                "criticalAt": settings.criticalThreshold,
                "force": forceIfInBand,
                "scope": scope.logSummary
            ])
            return
        }

        let last = settings.lastAlertedStage(for: scope)

        // 改阈值，或换账号 / 新周期且本作用域尚未记过同档。
        if forceIfInBand || scopeChanged {
            if !forceIfInBand, last?.1 == tipStage {
                AppLog.warn("AIUsage", "跳过额度提示：换作用域但同档已提示过", [
                    "remaining": percent,
                    "stage": tipStage.rawValue,
                    "scope": scope.logSummary
                ])
                return
            }
            settings.rememberAlert(provider: .cursor, stage: tipStage, scope: scope)
            presentNotice(percent: percent, stage: tipStage, resetsAt: cursor.resetsAt)
            AppLog.warn("AIUsage", forceIfInBand ? "改阈值强制提示" : "换账号/周期提示", [
                "stage": tipStage.rawValue,
                "remaining": percent,
                "scope": scope.logSummary,
                "scopeChanged": scopeChanged
            ])
            return
        }

        // 本进程首次采样：同账号同周期已提示过同档则跳过；换号/新周期（记忆未命中）或升级则弹。
        guard let previous else {
            let stageEscalated = last.map { Self.rank($0.1) < Self.rank(tipStage) } ?? true
            if last?.1 == tipStage {
                AppLog.warn("AIUsage", "跳过额度提示：同账号同周期同档已提示过", [
                    "remaining": percent,
                    "stage": tipStage.rawValue,
                    "scope": scope.logSummary
                ])
                return
            }
            if !stageEscalated {
                AppLog.warn("AIUsage", "跳过额度提示：首次采样档位未升级", [
                    "remaining": percent,
                    "stage": tipStage.rawValue,
                    "lastStage": last?.1.rawValue ?? "nil",
                    "scope": scope.logSummary
                ])
                return
            }
            settings.rememberAlert(provider: .cursor, stage: tipStage, scope: scope)
            presentNotice(percent: percent, stage: tipStage, resetsAt: cursor.resetsAt)
            AppLog.warn("AIUsage", "首次采样提示（新作用域或档位升级）", [
                "stage": tipStage.rawValue,
                "remaining": percent,
                "scope": scope.logSummary
            ])
            return
        }

        let crossed = Self.didCrossInto(
            stage: tipStage,
            from: previous,
            to: percent,
            abundant: settings.abundantThreshold,
            warning: settings.warningThreshold,
            critical: settings.criticalThreshold
        )
        let stageEscalated = last.map { Self.rank($0.1) < Self.rank(tipStage) } ?? false

        if !crossed, !stageEscalated {
            AppLog.warn("AIUsage", "跳过额度提示：未跌破新线且未升级档", [
                "remaining": percent,
                "prev": previous,
                "stage": tipStage.rawValue,
                "lastStage": last?.1.rawValue ?? "nil",
                "scope": scope.logSummary
            ])
            return
        }

        settings.rememberAlert(provider: .cursor, stage: tipStage, scope: scope)
        presentNotice(percent: percent, stage: tipStage, resetsAt: cursor.resetsAt)
    }

    private static func didCrossInto(
        stage: AIUsageStage,
        from previous: Int,
        to current: Int,
        abundant: Int,
        warning: Int,
        critical: Int
    ) -> Bool {
        let line: Int
        switch stage {
        case .critical: line = critical
        case .warning: line = warning
        case .abundant: line = abundant
        case .unknown: return false
        }
        return previous > line && current <= line
    }

    private static func rank(_ stage: AIUsageStage) -> Int {
        switch stage {
        case .unknown: return 0
        case .abundant: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    private func presentNotice(percent: Int, stage: AIUsageStage, resetsAt: Date?) {
        let id = "aiUsage.\(stage.rawValue).\(Int(Date().timeIntervalSince1970 * 1000))"
        IslandNoticeCenter.shared.present(
            .aiUsageAlert(
                id: id,
                providerName: L10n.AIUsage.providerCursor,
                remainingPercent: percent,
                stage: stage,
                resetsAt: resetsAt
            )
        )
        AppLog.warn("AIUsage", "已投递额度阈值瞬时通知", [
            "id": id,
            "stage": stage.rawValue,
            "remaining": percent,
            "abundantAt": settings.abundantThreshold,
            "warningAt": settings.warningThreshold,
            "criticalAt": settings.criticalThreshold
        ])
    }

    private static func userMessage(for error: Error) -> String {
        guard let err = error as? CursorAuthError else {
            return L10n.AIUsage.errorGeneric
        }
        switch err {
        case .databaseMissing, .tokenMissing:
            return L10n.AIUsage.errorNotSignedIn
        case .keychainDenied:
            return L10n.AIUsage.errorKeychain
        case .decryptFailed:
            return L10n.AIUsage.errorDecrypt
        case .httpStatus(401):
            return L10n.AIUsage.errorUnauthorized
        case .httpStatus:
            return L10n.AIUsage.errorNetwork
        case .decodeFailed:
            return L10n.AIUsage.errorGeneric
        case .offline:
            return L10n.AIUsage.errorNetwork
        }
    }
}
