import AppKit
import Combine
import CoreServices
import Foundation

/// 监视 Downloads：新文件稳定后若归因到 AirDrop，则投 D 档 tip。
@MainActor
final class AirDropReceiveSession: ObservableObject {
    static let shared = AirDropReceiveSession()

    @Published private(set) var latest: AirDropReceiveNotice?

    private var started = false
    private var directoryFD: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var knownPaths = Set<String>()
    private var pendingStability: [String: Task<Void, Never>] = [:]
    private var recentPresented: [String: Date] = [:]
    private let stabilityNanoseconds: UInt64 = 450_000_000
    private let dedupeWindow: TimeInterval = 60

    private init() {}

    private var tipEnabled: Bool {
        WidgetSettings.shared.isEnabled(AirDropReceiveTipWidget.manifest.id)
    }

    var downloadsDirectoryURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    func start() {
        guard !started else {
            AppLog.debug("AirDrop", "会话已在跑，跳过重复 start")
            return
        }
        started = true
        seedKnownPaths()
        openWatch()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanDirectory(reason: "poll")
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        AppLog.warn("AirDrop", "接收会话已启动", [
            "tipOn": tipEnabled,
            "dir": downloadsDirectoryURL.path,
            "known": knownPaths.count
        ])
    }

    func stop() {
        guard started else { return }
        closeWatch()
        pollTimer?.invalidate()
        pollTimer = nil
        for (_, task) in pendingStability { task.cancel() }
        pendingStability.removeAll()
        started = false
        AppLog.warn("AirDrop", "接收会话已停止")
    }

    /// 设置 / 测试台：挂一条假 tip。
    func presentSample(fileName: String = "Photo.jpg") {
        let path = downloadsDirectoryURL.appendingPathComponent(fileName).path
        let notice = AirDropReceiveNotice(
            id: "airdrop.sample.\(UUID().uuidString.prefix(8))",
            path: path,
            fileName: fileName
        )
        latest = notice
        presentNotice(notice)
        AppLog.info("AirDrop", "已投样张 tip", ["name": fileName])
    }

    /// 点 tip：按设置打开或访达选中，并撤 tip。
    @discardableResult
    func handleClick() -> Bool {
        guard let notice = latest else {
            AppLog.warn("AirDrop", "点击无效：无当前 tip")
            return false
        }
        let url = URL(fileURLWithPath: notice.path)
        let action = AirDropReceiveSettings.shared.clickAction
        AppLog.info("AirDrop", "点击 tip", [
            "name": notice.fileName,
            "action": action.rawValue,
            "exists": FileManager.default.fileExists(atPath: notice.path)
        ])
        switch action {
        case .revealInFinder:
            if FileManager.default.fileExists(atPath: notice.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(downloadsDirectoryURL)
            }
        case .openWithDefaultApp:
            if FileManager.default.fileExists(atPath: notice.path) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([downloadsDirectoryURL])
                AppLog.warn("AirDrop", "文件已不存在，改为打开下载目录", ["path": notice.path])
            }
        }
        IslandNoticeCenter.shared.dismiss(id: notice.id)
        if latest?.id == notice.id {
            latest = nil
        }
        return true
    }

    // MARK: - Watch

    private func seedKnownPaths() {
        knownPaths = Set(listDirectoryPaths())
    }

    private func openWatch() {
        closeWatch()
        let path = downloadsDirectoryURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            AppLog.warn("AirDrop", "无法监视下载目录", ["path": path, "errno": errno])
            return
        }
        directoryFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: DispatchQueue.main
        )
        src.setEventHandler { [weak self] in
            self?.scanDirectory(reason: "fsEvent")
        }
        src.setCancelHandler { [weak self] in
            if let self, self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }
        source = src
        src.resume()
        AppLog.debug("AirDrop", "已监视下载目录", ["path": path])
    }

    private func closeWatch() {
        source?.cancel()
        source = nil
        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
    }

    private func listDirectoryPaths() -> [String] {
        let dir = downloadsDirectoryURL
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url in
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if vals?.isDirectory == true || vals?.isRegularFile == true {
                return url.path
            }
            return nil
        }
    }

    private func scanDirectory(reason: String) {
        guard tipEnabled else { return }
        let paths = listDirectoryPaths()
        let current = Set(paths)
        let newcomers = current.subtracting(knownPaths)
        knownPaths = current.union(knownPaths)
        guard !newcomers.isEmpty else { return }

        AppLog.debug("AirDrop", "发现新条目", [
            "reason": reason,
            "count": newcomers.count
        ])

        for path in newcomers {
            scheduleStabilityCheck(path: path)
        }
        pruneRecent()
    }

    private func scheduleStabilityCheck(path: String) {
        pendingStability[path]?.cancel()
        pendingStability[path] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: stabilityNanoseconds)
            guard !Task.isCancelled else { return }
            pendingStability[path] = nil
            evaluateNewFile(path: path)
        }
    }

    private func evaluateNewFile(path: String) {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        let fileName = url.lastPathComponent
        if isDir.boolValue {
            // 文件夹也允许 tip（AirDrop 可传文件夹）。
        } else {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return
            }
        }

        let agent = Self.quarantineAgentBundleID(for: path)
        let whereFroms = Self.whereFroms(for: path)
        guard AirDropReceiveAttribution.isLikelyAirDropReceive(
            fileName: fileName,
            quarantineAgentBundleID: agent,
            whereFroms: whereFroms
        ) else {
            AppLog.debug("AirDrop", "新文件非隔空投送，跳过", [
                "name": fileName,
                "agent": agent ?? "",
                "whereFroms": whereFroms.count
            ])
            return
        }

        let now = Date()
        if let last = recentPresented[path], now.timeIntervalSince(last) < dedupeWindow {
            AppLog.debug("AirDrop", "同路径去抖，跳过", ["name": fileName])
            return
        }
        recentPresented[path] = now

        let notice = AirDropReceiveNotice(
            id: "airdrop.recv.\(UUID().uuidString.prefix(10))",
            path: path,
            fileName: fileName
        )
        latest = notice
        presentNotice(notice)
        AppLog.warn("AirDrop", "接收完成 tip 已投递", [
            "name": fileName,
            "agent": agent ?? "",
            "whereFroms": whereFroms.prefix(2).joined(separator: "|")
        ])
    }

    private func presentNotice(_ notice: AirDropReceiveNotice) {
        IslandNoticeCenter.shared.present(.airDropReceived(notice))
    }

    private func pruneRecent() {
        let now = Date()
        recentPresented = recentPresented.filter { now.timeIntervalSince($0.value) < dedupeWindow * 2 }
    }

    private static func quarantineAgentBundleID(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey]),
              let props = values.quarantineProperties,
              let agent = props["LSQuarantineAgentBundleIdentifierKey"] as? String,
              !agent.isEmpty
        else { return nil }
        return agent
    }

    private static func whereFroms(for path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        // Spotlight whereFroms；失败则空。
        guard let item = MDItemCreate(nil, path as CFString) else { return [] }
        guard let raw = MDItemCopyAttribute(item, kMDItemWhereFroms) else { return [] }
        if let list = raw as? [String] { return list }
        if let s = raw as? String { return [s] }
        return []
    }
}
