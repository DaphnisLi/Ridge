import CoreGraphics
import Foundation
import os

/// 统一带 tag 的日志；禁止裸 print。
enum AppLog {
    private static let logger = Logger(subsystem: "app.daphnis.Ridge", category: "App")

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
        case .error:
            logger.error("\(line, privacy: .public)")
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
