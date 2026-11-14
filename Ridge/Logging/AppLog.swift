import CoreGraphics
import Foundation
import os

/// 统一带 tag 的日志；禁止裸 print。
/// 文件：`~/Library/Logs/Ridge/app-YYYY-MM-DD.log`，最多保留 3 天；warn/error 落盘。
enum AppLog {
    private static let logger = Logger(subsystem: "app.daphnis.Ridge", category: "App")
    private static let fileQueue = DispatchQueue(label: "app.daphnis.Ridge.AppLog.file")
    private static let keepDays = 3

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `~/Library/Logs/Ridge`
    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ridge", isDirectory: true)
    }

    /// 当天日志文件（主落盘路径）。
    static func todayLogURL(date: Date = Date()) -> URL {
        let name = "app-\(dayFormatter.string(from: date)).log"
        return logsDirectory.appendingPathComponent(name, isDirectory: false)
    }

    /// 读取当天日志正文（尾部截断，便于塞进邮件 / 诊断）。
    static func readTodayLog(maxBytes: Int = 240_000) -> String? {
        let url = todayLogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let slice: Data
        if data.count <= maxBytes {
            slice = data
        } else {
            slice = data.suffix(maxBytes)
        }
        var text = String(data: slice, encoding: .utf8) ?? String(decoding: slice, as: UTF8.self)
        if data.count > maxBytes {
            text = "…（仅附带当日日志末尾 \(maxBytes) 字节）\n" + text
        }
        return text
    }

    static func debug(_ tag: String, _ message: String, _ fields: [String: Any] = [:]) {
        log(level: .debug, tag: tag, message: message, fields: fields)
    }

    static func info(_ tag: String, _ message: String, _ fields: [String: Any] = [:]) {
        log(level: .info, tag: tag, message: message, fields: fields)
    }

    static func warn(_ tag: String, _ message: String, _ fields: [String: Any] = [:]) {
        log(level: .warning, tag: tag, message: message, fields: fields)
    }

    static func error(_ tag: String, _ message: String, _ fields: [String: Any] = [:]) {
        log(level: .error, tag: tag, message: message, fields: fields)
    }

    private enum Level {
        case debug, info, warning, error
    }

    private static func log(level: Level, tag: String, message: String, fields: [String: Any]) {
        let suffix: String
        if fields.isEmpty {
            suffix = ""
        } else {
            let parts = fields.keys.sorted().map { key in
                "\(key)=\(stringify(fields[key]!))"
            }
            suffix = " | " + parts.joined(separator: " ")
        }
        let line = "[\(tag)] \(message)\(suffix)"
        switch level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
            appendToFile(level: "warn", line: line)
        case .error:
            logger.error("\(line, privacy: .public)")
            appendToFile(level: "error", line: line)
        }
    }

    private static func appendToFile(level: String, line: String) {
        fileQueue.async {
            let fm = FileManager.default
            let dir = logsDirectory
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let stamp = ISO8601DateFormatter().string(from: Date())
            let row = "\(stamp) \(level) \(line)\n"
            guard let data = row.data(using: .utf8) else { return }

            let dayURL = todayLogURL()
            // /tmp 镜像当天，便于本机无 TCC 时排查。
            let tmpURL = URL(fileURLWithPath: "/tmp/ridge-app.log")
            for fileURL in [dayURL, tmpURL] {
                if fm.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }

            pruneOldLogsLocked(keepingDays: keepDays)
        }
    }

    /// 删除超过保留天数的 `app-YYYY-MM-DD.log`（须在 fileQueue 上调用）。
    private static func pruneOldLogsLocked(keepingDays: Int) {
        let fm = FileManager.default
        let dir = logsDirectory
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -keepingDays, to: cal.startOfDay(for: Date())) else {
            return
        }

        for url in items {
            let name = url.lastPathComponent
            guard name.hasPrefix("app-"), name.hasSuffix(".log") else { continue }
            // app-YYYY-MM-DD.log
            let stamp = String(name.dropFirst(4).dropLast(4))
            guard let fileDay = dayFormatter.date(from: stamp) else { continue }
            if fileDay < cutoff {
                try? fm.removeItem(at: url)
            }
        }

        // 兼容旧版单文件 app.log：超过保留期则删。
        let legacy = dir.appendingPathComponent("app.log")
        if let attrs = try? fm.attributesOfItem(atPath: legacy.path),
           let modified = attrs[.modificationDate] as? Date,
           modified < cutoff {
            try? fm.removeItem(at: legacy)
        }
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let v as String: return v
        case let v as Bool: return v ? "true" : "false"
        case let v as Int: return String(v)
        case let v as Double: return String(format: "%.3f", v)
        case let v as CGFloat: return String(format: "%.3f", Double(v))
        default: return String(describing: value)
        }
    }
}
