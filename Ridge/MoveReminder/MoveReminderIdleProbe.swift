import CoreGraphics
import Foundation
import IOKit

/// 系统级「多久没输入」探测：优先 `HIDIdleTime`，失败再回落 `CGEventSource`。
/// 不装 Event Tap，不需要辅助功能 / 输入监控权限。
enum MoveReminderIdleProbe {
    /// 距离上次键鼠/触控等输入的秒数；读失败返回较大值（偏向「已离开」以免误报）。
    static func secondsSinceLastInput() -> TimeInterval {
        if let hid = hidIdleSeconds() {
            return hid
        }
        return cgEventIdleSeconds()
    }

    // MARK: - IOHIDSystem HIDIdleTime（纳秒）

    private static func hidIdleSeconds() -> TimeInterval? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let prop = IORegistryEntryCreateCFProperty(
            entry,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        else { return nil }

        let nanos: UInt64
        if let number = prop as? NSNumber {
            nanos = number.uint64Value
        } else if CFGetTypeID(prop) == CFNumberGetTypeID() {
            var value: UInt64 = 0
            CFNumberGetValue((prop as! CFNumber), .longLongType, &value)
            nanos = value
        } else {
            return nil
        }
        return TimeInterval(nanos) / 1_000_000_000
    }

    // MARK: - CGEventSource 回落

    private static func cgEventIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .scrollWheel,
            .flagsChanged
        ]
        var best = TimeInterval.greatestFiniteMagnitude
        for type in types {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if seconds.isFinite, seconds >= 0 {
                best = min(best, seconds)
            }
        }
        if best == .greatestFiniteMagnitude {
            return 24 * 3600
        }
        return best
    }
}
