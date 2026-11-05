import Combine
import Foundation

/// AI 额度会话：定时刷新 Cursor、按阈值投递岛内通知。
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

    private init() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reevaluateSensing(reason: "settings")
                // 阈值改动会清空去重记忆；按当前剩余立刻重判三档是否该弹。
                self?.maybePresentThresholdNotice()
            }
            .store(in: &settingsObservers)
    }

    func start() {
        guard !started else { return }
        started = true
        AppLog.warn("AIUsage", "会话启动", ["sensing": settings.sensingEnabled])
        reevaluateSensing(reason: "start")
        Task { await refresh(reason: "start") }
    }

    func refresh(reason: String) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        AppLog.warn("AIUsage", "开始刷新用量", ["reason": reason])

        var providers: [AIUsageProviderSnapshot] = []
        do {
            let cursor = try await CursorUsageClient.fetchSnapshot()
            providers.append(cursor)
            lastError = nil
        } catch {
            let message = Self.userMessage(for: error)
            lastError = message
            providers.append(
                AIUsageProviderSnapshot(
                    id: .cursor,
                    planLabel: nil,
                    accountHint: nil,
                    windows: [],
                    onDemand: nil,
                    fetchedAt: Date(),
                    errorMessage: message,
                    isStale: true
                )
            )
            AppLog.warn("AIUsage", "Cursor 刷新失败", ["reason": reason, "message": message])
        }

        snapshot = AIUsageSnapshot(providers: providers, updatedAt: Date())
        maybePresentThresholdNotice()
    }

    private func reevaluateSensing(reason: String) {
        timer?.invalidate()
        timer = nil
        guard settings.sensingEnabled else {
            AppLog.info("AIUsage", "感知已关闭", ["reason": reason])
            return
        }
        let minutes = max(settings.refreshMinutes, 5)
        let timer = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(reason: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        AppLog.debug("AIUsage", "已安排定时刷新", ["minutes": minutes, "reason": reason])
    }

    private func maybePresentThresholdNotice() {
        guard settings.sensingEnabled else {
            AppLog.warn("AIUsage", "跳过阈值提示：感知已关闭")
            return
        }
        guard let cursor = snapshot?.cursor,
              cursor.errorMessage == nil,
              let remaining = cursor.remainingPercent
        else {
            AppLog.warn("AIUsage", "跳过阈值提示：无有效剩余", [
                "error": snapshot?.cursor?.errorMessage ?? "nil"
            ])
            return
        }

        let stage = settings.stage(forRemaining: remaining)
        // 百分比必须是探针当前剩余，禁止用档位标称 60/30/10 顶替。
        let percent = Int(remaining.rounded())
        let last = settings.lastAlertedStage()

        // 高于充裕触发线：展示仍为充裕（绿），但不弹；用 unknown 仅作去重记忆。
        if !settings.isWithinAbundantTipBand(remaining) {
            if last?.0 != .cursor || last?.1 != .unknown {
                settings.rememberAlert(provider: .cursor, stage: .unknown)
            }
            AppLog.warn("AIUsage", "跳过阈值提示：高于充裕线", [
                "remaining": percent,
                "abundantAt": settings.abundantThreshold,
                "displayStage": stage.rawValue
            ])
            return
        }

        // 已落入充裕 / 警戒 / 截流触发带：跨档弹一次；同态不重复。
        if let last, last.0 == .cursor, last.1 == stage {
            AppLog.warn("AIUsage", "跳过阈值提示：同态已提示过", [
                "remaining": percent,
                "stage": stage.rawValue
            ])
            return
        }
        settings.rememberAlert(provider: .cursor, stage: stage)
        presentNotice(percent: percent, stage: stage, resetsAt: cursor.resetsAt)
    }

    private func presentNotice(percent: Int, stage: AIUsageStage, resetsAt: Date?) {
        IslandNoticeCenter.shared.present(
            .aiUsageAlert(
                id: "aiUsage.\(stage.rawValue)",
                providerName: L10n.AIUsage.providerCursor,
                remainingPercent: percent,
                stage: stage,
                resetsAt: resetsAt
            )
        )
        AppLog.warn("AIUsage", "已投递额度阈值瞬时通知", [
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
