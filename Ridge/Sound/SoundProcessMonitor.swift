import AppKit
import CoreAudio
import Foundation

/// 扫描 CoreAudio process objects，按 App 聚合正在输出的音源。
enum SoundProcessMonitor {
    struct RawProcess {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let isRunningOutput: Bool
    }

    static func snapshot(excludingBundleIDs: Set<String> = []) -> [RawProcess] {
        let ids: [AudioObjectID] = CoreAudioProperty.getArray(
            object: .system,
            kAudioHardwarePropertyProcessObjectList
        )
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return ids.compactMap { id -> RawProcess? in
            guard let pid: pid_t = CoreAudioProperty.get(object: id, kAudioProcessPropertyPID) else {
                return nil
            }
            if pid == selfPID { return nil }
            let bundleID = CoreAudioProperty.getCFString(object: id, kAudioProcessPropertyBundleID)
            if let bundleID, excludingBundleIDs.contains(bundleID) { return nil }
            let runningOut: UInt32 = CoreAudioProperty.get(object: id, kAudioProcessPropertyIsRunningOutput) ?? 0
            return RawProcess(
                objectID: id,
                pid: pid,
                bundleID: bundleID,
                isRunningOutput: runningOut != 0
            )
        }
    }

    /// 聚合成 UI 行；只关心输出播放 / 宽限期 / 已被接管的 App。
    static func aggregatedRows(
        volumes: [String: Double],
        muted: [String: Bool],
        lingerKeys: Set<String>,
        controlledKeys: Set<String>
    ) -> [SoundAppRow] {
        let raw = snapshot()
        var buckets: [String: (
            bundleID: String?,
            name: String,
            icon: NSImage?,
            objects: [AudioObjectID],
            pids: [pid_t],
            playing: Bool
        )] = [:]

        for process in raw {
            let key = process.bundleID ?? "pid:\(process.pid)"
            let app = NSRunningApplication(processIdentifier: process.pid)
            let name = app?.localizedName
                ?? process.bundleID
                ?? "PID \(process.pid)"
            let icon = app?.icon
            var bucket = buckets[key] ?? (
                bundleID: process.bundleID,
                name: name,
                icon: icon,
                objects: [],
                pids: [],
                playing: false
            )
            bucket.objects.append(process.objectID)
            if !bucket.pids.contains(process.pid) {
                bucket.pids.append(process.pid)
            }
            bucket.playing = bucket.playing || process.isRunningOutput
            if bucket.icon == nil { bucket.icon = icon }
            if bucket.name.isEmpty { bucket.name = name }
            buckets[key] = bucket
        }

        let keys = Set(buckets.keys).union(lingerKeys)
        return keys.compactMap { key -> SoundAppRow? in
            guard let bucket = buckets[key] else { return nil }
            let show = bucket.playing || lingerKeys.contains(key) || controlledKeys.contains(key)
            guard show else { return nil }
            return SoundAppRow(
                key: key,
                bundleID: bucket.bundleID,
                name: bucket.name,
                icon: bucket.icon,
                processObjectIDs: bucket.objects,
                pids: bucket.pids,
                isPlaying: bucket.playing,
                volume: volumes[key] ?? 1,
                isMuted: muted[key] ?? false,
                isControlled: controlledKeys.contains(key)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying && !rhs.isPlaying }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
