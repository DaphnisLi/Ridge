import Foundation
import SQLite3

/// 从 Safari 包 / Chromium History 读下载总长与已收字节，供进度环使用（禁止假 %）。
enum DownloadProgressLookup {
    struct Snapshot: Equatable {
        var receivedBytes: Int64?
        var totalBytes: Int64?
    }

    /// SQLite 复制绑定字符串（`SQLITE_TRANSIENT`）。
    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    /// 按临时件路径与成品名查进度；无总长则 `totalBytes == nil`。
    static func snapshot(tempURL: URL, displayName: String) -> Snapshot {
        let name = tempURL.lastPathComponent.lowercased()
        if name.hasSuffix(".download") {
            return safariPackage(at: tempURL)
        }
        return chromiumDownloads(
            currentPath: tempURL.path,
            targetFileName: displayName
        )
    }

    // MARK: - Safari `.download` 包

    private static func safariPackage(at packageURL: URL) -> Snapshot {
        let infoURL = packageURL.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return Snapshot(receivedBytes: nil, totalBytes: nil)
        }
        let received = int64(dict["DownloadEntryProgressBytesSoFar"])
            ?? int64(dict["DownloadEntryBytesLoaded"])
        let total = int64(dict["DownloadEntryProgressTotalToLoad"])
            ?? int64(dict["DownloadEntryBytesExpected"])
        return Snapshot(
            receivedBytes: received.flatMap { $0 >= 0 ? $0 : nil },
            totalBytes: total.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let n as Int64: return n
        case let n as Int: return Int64(n)
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s)
        default: return nil
        }
    }

    // MARK: - Chromium History `downloads`

    private static let chromiumHistoryRoots: [String] = [
        "Google/Chrome",
        "Google/Chrome Beta",
        "Google/Chrome Canary",
        "Microsoft Edge",
        "BraveSoftware/Brave-Browser",
        "Arc/User Data",
        "com.operasoftware.Opera",
        "Vivaldi",
    ]

    private static var cachedChromium: (pathKey: String, at: Date, snap: Snapshot)?
    private static let chromiumCacheTTL: TimeInterval = 1.2

    private static func chromiumDownloads(currentPath: String, targetFileName: String) -> Snapshot {
        let pathKey = currentPath + "|" + targetFileName
        if let cached = cachedChromium,
           cached.pathKey == pathKey,
           Date().timeIntervalSince(cached.at) < chromiumCacheTTL {
            return cached.snap
        }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        guard let support else {
            return Snapshot(receivedBytes: nil, totalBytes: nil)
        }

        var best: Snapshot?
        for root in chromiumHistoryRoots {
            let base = support.appendingPathComponent(root, isDirectory: true)
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for profile in profiles {
                let history = profile.appendingPathComponent("History")
                guard FileManager.default.fileExists(atPath: history.path) else { continue }
                if let snap = queryChromiumHistory(
                    historyURL: history,
                    currentPath: currentPath,
                    targetFileName: targetFileName
                ), snap.totalBytes != nil || snap.receivedBytes != nil {
                    best = snap
                    if snap.totalBytes != nil { break }
                }
            }
            if best?.totalBytes != nil { break }
        }

        let snap = best ?? Snapshot(receivedBytes: nil, totalBytes: nil)
        cachedChromium = (pathKey, Date(), snap)
        return snap
    }

    private static func queryChromiumHistory(
        historyURL: URL,
        currentPath: String,
        targetFileName: String
    ) -> Snapshot? {
        let fm = FileManager.default
        let stamp = UUID().uuidString
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(
            "ridge-dl-hist-\(stamp)",
            isDirectory: true
        )
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        defer { try? fm.removeItem(at: tmpDir) }

        let tmpHistory = tmpDir.appendingPathComponent("History")
        do {
            try fm.copyItem(at: historyURL, to: tmpHistory)
            let wal = URL(fileURLWithPath: historyURL.path + "-wal")
            let shm = URL(fileURLWithPath: historyURL.path + "-shm")
            if fm.fileExists(atPath: wal.path) {
                try? fm.copyItem(at: wal, to: tmpDir.appendingPathComponent("History-wal"))
            }
            if fm.fileExists(atPath: shm.path) {
                try? fm.copyItem(at: shm, to: tmpDir.appendingPathComponent("History-shm"))
            }
        } catch {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            tmpHistory.path,
            &db,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT received_bytes, total_bytes, current_path, target_path
        FROM downloads
        WHERE current_path = ?1
           OR current_path LIKE ?2
           OR target_path = ?3
           OR target_path LIKE ?4
        ORDER BY start_time DESC
        LIMIT 8;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let likeCurrent = "%\(URL(fileURLWithPath: currentPath).lastPathComponent)"
        let targetExact = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(targetFileName)
            .path ?? targetFileName
        let likeTarget = "%/\(targetFileName)"

        bindText(stmt, 1, currentPath)
        bindText(stmt, 2, likeCurrent)
        bindText(stmt, 3, targetExact)
        bindText(stmt, 4, likeTarget)

        let tempLeaf = URL(fileURLWithPath: currentPath).lastPathComponent
        while sqlite3_step(stmt) == SQLITE_ROW {
            let received = sqlite3_column_int64(stmt, 0)
            let total = sqlite3_column_int64(stmt, 1)
            let current = stringColumn(stmt, 2) ?? ""
            let target = stringColumn(stmt, 3) ?? ""
            let matchesCurrent = !current.isEmpty && (
                current == currentPath
                    || current.hasSuffix("/" + tempLeaf)
                    || URL(fileURLWithPath: current).lastPathComponent == tempLeaf
            )
            let looksLikePlaceholder = targetFileName.isEmpty
                || targetFileName.hasPrefix("Unconfirmed")
                || targetFileName == "正在下载"
            let matchesTarget = !looksLikePlaceholder && (
                target == targetExact
                    || target.hasSuffix("/" + targetFileName)
                    || URL(fileURLWithPath: target).lastPathComponent == targetFileName
            )
            guard matchesCurrent || matchesTarget else { continue }
            return Snapshot(
                receivedBytes: received >= 0 ? received : nil,
                totalBytes: total > 0 ? total : nil
            )
        }
        return nil
    }

    private static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        value.withCString { cString in
            _ = sqlite3_bind_text(stmt, index, cString, -1, sqliteTransient)
        }
    }

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
