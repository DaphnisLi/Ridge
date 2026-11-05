import Foundation

/// 读取本机 Cursor 登录态并拉取周期用量（非官方 Dashboard Connect RPC）。
enum CursorUsageClient {
    private static let stateDBRelativePath =
        "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    private static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!
    private static let planInfoURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
    )!

    struct LocalAuth {
        let accessToken: String
        let email: String?
        let membership: String?
    }

    private struct PlanInfo {
        var planName: String?
        var price: String?
        var isTrial: Bool
    }

    static func readLocalAuth() throws -> LocalAuth {
        let path = NSHomeDirectory() + "/" + stateDBRelativePath
        guard FileManager.default.fileExists(atPath: path) else {
            throw CursorAuthError.databaseMissing
        }
        let values = try readItemTable(
            path: path,
            keys: [
                "cursorAuth/accessToken",
                "cursorAuth/cachedEmail",
                "cursorAuth/stripeMembershipType"
            ]
        )
        guard let stored = values["cursorAuth/accessToken"], !stored.isEmpty else {
            throw CursorAuthError.tokenMissing
        }
        let token = try CursorSafeStorage.decryptToken(stored)
        return LocalAuth(
            accessToken: token,
            email: values["cursorAuth/cachedEmail"],
            membership: values["cursorAuth/stripeMembershipType"]
        )
    }

    static func fetchSnapshot() async throws -> AIUsageProviderSnapshot {
        let auth = try readLocalAuth()
        async let usageJSON = postDashboardJSON(url: usageURL, token: auth.accessToken)
        async let planJSON = postDashboardJSON(url: planInfoURL, token: auth.accessToken)
        let json = try await usageJSON
        let planPayload = try? await planJSON
        let planInfo = Self.parsePlanInfo(planPayload)

        let planUsage = json["planUsage"] as? [String: Any] ?? [:]
        let totalUsed = doubleValue(planUsage["totalPercentUsed"]) ?? 0
        let autoUsed = doubleValue(planUsage["autoPercentUsed"])
        let planCycleEnd = (planPayload?["planInfo"] as? [String: Any])?["billingCycleEnd"]
        let resetAt = parseCycleDate(json["billingCycleEnd"])
            ?? parseCycleDate(planCycleEnd)
        var windows: [AIUsageWindow] = [
            AIUsageWindow(
                id: "plan.total",
                title: L10n.AIUsage.windowPlanTotal,
                usedPercent: totalUsed,
                resetsAt: resetAt
            )
        ]
        if let autoUsed {
            windows.append(
                AIUsageWindow(
                    id: "plan.auto",
                    title: L10n.AIUsage.windowPlanAuto,
                    usedPercent: autoUsed,
                    resetsAt: resetAt
                )
            )
        }

        let onDemand = parseOnDemand(json["spendLimitUsage"] as? [String: Any])
        let planLabel = resolvePlanLabel(
            planInfo: planInfo,
            membership: auth.membership
        )
        let hint: String? = {
            guard let email = auth.email, email.contains("@") else { return auth.email }
            let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return email }
            let name = parts[0]
            let masked = name.count <= 2
                ? String(repeating: "*", count: name.count)
                : String(name.prefix(2)) + "***"
            return "\(masked)@\(parts[1])"
        }()

        AppLog.warn("AIUsage", "Cursor 用量已刷新", [
            "remaining": Int(max(0, 100 - totalUsed)),
            "plan": planLabel ?? auth.membership ?? "?",
            "planName": planInfo?.planName ?? "nil",
            "trial": planInfo?.isTrial ?? false,
            "onDemandSpent": onDemand.map { String(format: "%.2f", $0.spentUSD) } ?? "nil",
            "windows": windows.count
        ])

        return AIUsageProviderSnapshot(
            id: .cursor,
            planLabel: planLabel,
            accountHint: hint,
            windows: windows,
            onDemand: onDemand,
            fetchedAt: Date(),
            errorMessage: nil,
            isStale: false
        )
    }

    /// `spendLimitUsage`：金额为美元或美分混用，优先 overall*；无限额则 spent=0。
    private static func parseOnDemand(_ raw: [String: Any]?) -> AIUsageOnDemandSpend? {
        guard let raw else { return nil }
        let limit = doubleValue(raw["overallLimit"])
            ?? doubleValue(raw["individualLimit"])
            ?? doubleValue(raw["pooledLimit"])
            ?? 0
        let remaining = doubleValue(raw["overallRemaining"])
            ?? doubleValue(raw["pooledRemaining"])
        // Cursor 有时给美分整数；≥1000 且能整除 100 时按美分处理。
        func asUSD(_ value: Double) -> Double {
            if value >= 1000, value.truncatingRemainder(dividingBy: 1) == 0 {
                return value / 100
            }
            return value
        }
        let limitUSD = asUSD(limit)
        let spentUSD: Double
        if let remaining {
            spentUSD = max(asUSD(limit) - asUSD(remaining), 0)
        } else {
            spentUSD = 0
        }
        // 限额与花费都是 0 也返回结构，设置页仍展示「按需」槽。
        return AIUsageOnDemandSpend(spentUSD: spentUSD, limitUSD: limitUSD)
    }

    private static func postDashboardJSON(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AppLog.warn("AIUsage", "Cursor Dashboard 请求失败", [
                "path": url.lastPathComponent,
                "error": error.localizedDescription
            ])
            throw CursorAuthError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw CursorAuthError.offline }
        guard http.statusCode == 200 else {
            AppLog.warn("AIUsage", "Cursor Dashboard HTTP 非 200", [
                "path": url.lastPathComponent,
                "status": http.statusCode
            ])
            throw CursorAuthError.httpStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorAuthError.decodeFailed
        }
        return json
    }

    private static func parsePlanInfo(_ json: [String: Any]?) -> PlanInfo? {
        guard let json else { return nil }
        let info = json["planInfo"] as? [String: Any] ?? json
        let name = info["planName"] as? String
        let price = info["price"] as? String
        let blob = [name, price, info["description"] as? String]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let isTrial = blob.contains("trial")
            || blob.contains("试用")
            || blob.contains("free trial")
            || blob.contains("pro trial")
        return PlanInfo(planName: name, price: price, isTrial: isTrial)
    }

    /// 优先 GetPlanInfo；试用显示「试用」或「Pro 试用」。
    private static func resolvePlanLabel(planInfo: PlanInfo?, membership: String?) -> String? {
        if let planInfo, planInfo.isTrial {
            if let name = planInfo.planName, !name.isEmpty,
               !name.lowercased().contains("trial"),
               name.lowercased() != "free"
            {
                return "\(name) \(L10n.AIUsage.planTrial)"
            }
            return L10n.AIUsage.planTrial
        }
        if let name = planInfo?.planName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        guard let membership, !membership.isEmpty else { return nil }
        switch membership.lowercased() {
        case "free", "hobby":
            return L10n.AIUsage.planFree
        case "pro", "pro_plus", "pro+", "ultra", "business", "enterprise", "team":
            return membership
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        default:
            return membership.capitalized
        }
    }

    // MARK: - SQLite（只读 ItemTable，避免复制超大 state.vscdb）

    private static func readItemTable(path: String, keys: [String]) throws -> [String: String] {
        // 用系统 sqlite3 CLI，避免把 5GB 库链进 App。
        let placeholders = keys.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
        let sql = "SELECT key, value FROM ItemTable WHERE key IN (\(placeholders));"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\t", path, sql]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw CursorAuthError.databaseMissing
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            AppLog.warn("AIUsage", "sqlite3 读 Cursor state 失败", [
                "status": process.terminationStatus,
                "err": String(err.prefix(120))
            ])
            throw CursorAuthError.databaseMissing
        }
        var result: [String: String] = [:]
        let text = String(data: outData, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let key = String(line[..<tab])
            let value = String(line[line.index(after: tab)...])
            result[key] = value
        }
        return result
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// Cursor 返回毫秒时间戳字符串。
    private static func parseCycleDate(_ any: Any?) -> Date? {
        let raw: Double?
        switch any {
        case let s as String: raw = Double(s)
        case let n as Double: raw = n
        case let n as Int: raw = Double(n)
        case let n as NSNumber: raw = n.doubleValue
        default: raw = nil
        }
        guard let millis = raw, millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
