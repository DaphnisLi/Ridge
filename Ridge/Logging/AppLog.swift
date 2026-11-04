import CoreGraphics
import Foundation
import os

/// 统一带 tag 的日志；禁止裸 print。
enum AppLog {
    private static let logger = Logger(subsystem: "app.daphnis.Ridge", category: "App")
    /// 统一日志在沙箱/权限下常读不到；warn/error 同步落盘便于排查焦点/命中。
    private static let fileQueue = DispatchQueue(label: "app.daphnis.Ridge.AppLog.file")
    private static let fileURLs: [URL] = {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        // /tmp 便于 agent 无 TCC 时直接读。
        return [
            homeDir.appendingPathComponent("app.log", isDirectory: false),
            URL(fileURLWithPath: "/tmp/ridge-app.log")
        ]
    }()

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
            let stamp = ISO8601DateFormatter().string(from: Date())
            let row = "\(stamp) \(level) \(line)\n"
            guard let data = row.data(using: .utf8) else { return }
            for fileURL in fileURLs {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
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
