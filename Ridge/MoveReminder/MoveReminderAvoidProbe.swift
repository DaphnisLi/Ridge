import AppKit
import CoreAudio
import CoreGraphics
import EventKit
import Foundation

/// 智能避让：全屏演示 / 日历会议中 / 麦克风占用 → 暂停累计（不清零）。
enum MoveReminderAvoidProbe {
    struct Snapshot: Equatable {
        var shouldPause: Bool
        var reason: String
    }

    static func evaluate(smartAvoidEnabled: Bool) -> Snapshot {
        guard smartAvoidEnabled else {
            return Snapshot(shouldPause: false, reason: "off")
        }
        if isFrontmostFullscreen() {
            return Snapshot(shouldPause: true, reason: "fullscreen")
        }
        if isMicrophoneInUse() {
            return Snapshot(shouldPause: true, reason: "microphone")
        }
        if isInCalendarMeetingNow() {
            return Snapshot(shouldPause: true, reason: "calendarMeeting")
        }
        return Snapshot(shouldPause: false, reason: "none")
    }

    // MARK: - Fullscreen（与 FullscreenMonitor 同思路，无辅助功能）

    private static func isFrontmostFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        let frontPID = front.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for screen in NSScreen.screens {
            let screenW = screen.frame.width
            let screenH = screen.frame.height
            for info in infoList {
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == frontPID else {
                    continue
                }
                guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let w = bounds["Width"], let h = bounds["Height"]
                else { continue }
                // 接近铺满屏：原生全屏 / 演示模式。
                if w >= screenW * 0.95, h >= screenH * 0.95 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Microphone（CoreAudio DeviceIsRunningSomewhere，不弹权限）

    private static func isMicrophoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else { return false }

        for device in devices {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &inputAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0
            else { continue }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr
            else { continue }
            if running != 0 { return true }
        }
        return false
    }

    // MARK: - Calendar（仅在已授权时只读；不主动申请权限）

    private static func isInCalendarMeetingNow() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        let ok: Bool
        if #available(macOS 14.0, *) {
            ok = status == .fullAccess
        } else {
            ok = status == .authorized
        }
        guard ok else { return false }

        let store = EKEventStore()
        let now = Date()
        let windowEnd = now.addingTimeInterval(60)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)
        return events.contains { event in
            !event.isAllDay
                && event.startDate <= now
                && event.endDate > now
        }
    }
}
