import AppKit
import Darwin
import Foundation

/// 监视进程的结束结果（尽力从 kqueue NOTE_EXITSTATUS 读取）。
enum ProjectWatchOutcome: Hashable {
    case succeeded
    case failed(code: Int32)
    case signaled(signal: Int32)
    case unknown

    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var isFailure: Bool {
        switch self {
        case .failed, .signaled: return true
        case .succeeded, .unknown: return false
        }
    }
}

enum ProjectProcessSupport {
    /// 进程真实启动时间（libproc）；失败则 nil。
    static func startDate(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard ret == size, info.pbi_start_tvsec > 0 else { return nil }
        let seconds = TimeInterval(info.pbi_start_tvsec)
            + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }

    /// 等待 pid 退出并解析退出状态。`isCancelled` 为 true 时返回 `nil`（可中断）。
    static func waitForExit(
        pid: Int32,
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> ProjectWatchOutcome? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let outcome = waitForExitSync(pid: pid, isCancelled: isCancelled)
                continuation.resume(returning: outcome)
            }
        }
    }

    /// 查找进程 stdout/stderr 指向的常规文件（常见于 nohup / 脚本重定向的 .log）。
    static func discoverLogPath(pid: Int32) -> String? {
        let focused = ProjectShell.run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-nP", "-p", "\(pid)", "-d", "1,2"],
            timeout: 3
        )
        let fromStd = parseLogCandidates(from: focused.stdout)
        if let best = pickBestLog(fromStd) {
            return best
        }

        let broad = ProjectShell.run(
            "/usr/sbin/lsof",
            arguments: ["-a", "-nP", "-p", "\(pid)", "-d", "0-9"],
            timeout: 4
        )
        return pickBestLog(parseLogCandidates(from: broad.stdout))
    }

    static func openLog(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private static func waitForExitSync(
        pid: Int32,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> ProjectWatchOutcome? {
        let kq = kqueue()
        guard kq >= 0 else {
            AppLog.warn("Projects", "kqueue 创建失败，回退轮询监视", ["pid": pid])
            return pollUntilGone(pid: pid, isCancelled: isCancelled)
        }
        defer { close(kq) }

        var change = kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: NOTE_EXIT | UInt32(NOTE_EXITSTATUS),
            data: 0,
            udata: nil
        )
        if kevent(kq, &change, 1, nil, 0, nil) != 0 {
            AppLog.warn("Projects", "kqueue 注册退出监视失败，回退轮询", [
                "pid": pid,
                "errno": errno
            ])
            return pollUntilGone(pid: pid, isCancelled: isCancelled)
        }

        AppLog.debug("Projects", "已注册进程退出监视", ["pid": pid])
        while true {
            if isCancelled() { return nil }
            var event = kevent()
            var timeout = timespec(tv_sec: 0, tv_nsec: 400_000_000)
            let n = kevent(kq, nil, 0, &event, 1, &timeout)
            if n > 0 {
                let status = Int32(truncatingIfNeeded: event.data)
                let outcome = decodeWaitStatus(status)
                AppLog.info("Projects", "进程退出状态已解析", [
                    "pid": pid,
                    "raw": status,
                    "outcome": outcomeLabel(outcome)
                ])
                return outcome
            }
            if n < 0 && errno != EINTR {
                AppLog.warn("Projects", "kqueue 等待退出出错，回退轮询", [
                    "pid": pid,
                    "errno": errno
                ])
                return pollUntilGone(pid: pid, isCancelled: isCancelled)
            }
        }
    }

    private static func pollUntilGone(
        pid: Int32,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> ProjectWatchOutcome? {
        while kill(pid, 0) == 0 {
            if isCancelled() { return nil }
            usleep(200_000)
        }
        return .unknown
    }

    /// Darwin wait status（不用不可用的 WIF* 宏）。
    private static func decodeWaitStatus(_ status: Int32) -> ProjectWatchOutcome {
        let wstatus = status & 0o177
        if wstatus == 0 {
            let code = (status >> 8) & 0xff
            return code == 0 ? .succeeded : .failed(code: code)
        }
        if wstatus != 0o177 {
            return .signaled(signal: wstatus)
        }
        return .unknown
    }

    private static func outcomeLabel(_ outcome: ProjectWatchOutcome) -> String {
        switch outcome {
        case .succeeded: return "succeeded"
        case .failed(let code): return "failed:\(code)"
        case .signaled(let signal): return "signaled:\(signal)"
        case .unknown: return "unknown"
        }
    }

    private static func parseLogCandidates(from stdout: String) -> [(path: String, fd: String, size: UInt64)] {
        var results: [(String, String, UInt64)] = []
        for line in stdout.split(whereSeparator: \.isNewline) {
            let parts = String(line).split(whereSeparator: \.isWhitespace).map(String.init)
            // lsof: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME...
            guard parts.count >= 9, parts[4] == "REG" else { continue }
            let fd = parts[3]
            let path = parts[8...].joined(separator: " ")
            guard isPlausibleLogPath(path) else { continue }
            let size = UInt64(parts[6]) ?? fileSize(path)
            results.append((path, fd, size))
        }
        return results
    }

    private static func isPlausibleLogPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let lower = path.lowercased()
        if lower.hasSuffix(".log") || lower.hasSuffix(".out") || lower.hasSuffix(".err") {
            return true
        }
        // stdout/stderr 重定向到无扩展名的文件也接受
        if lower.contains("/log") || lower.contains(".out.") || lower.contains(".err.") {
            return true
        }
        // 排除可执行文件 / dylib
        if lower.hasSuffix(".dylib") || lower.hasSuffix(".so") || lower.contains(".framework/") {
            return false
        }
        return lower.contains(".log") || lower.hasSuffix(".txt")
    }

    private static func pickBestLog(_ items: [(path: String, fd: String, size: UInt64)]) -> String? {
        guard !items.isEmpty else { return nil }
        // 优先 stderr（fd 2），且有内容；否则 stdout；否则体积最大。
        let stderr = items.filter { $0.fd.hasPrefix("2") }
        if let rich = stderr.filter({ $0.size > 0 }).max(by: { $0.size < $1.size }) {
            return rich.path
        }
        let stdout = items.filter { $0.fd.hasPrefix("1") }
        if let rich = stdout.filter({ $0.size > 0 }).max(by: { $0.size < $1.size }) {
            return rich.path
        }
        if let anyErr = stderr.first { return anyErr.path }
        if let anyOut = stdout.first { return anyOut.path }
        return items.max(by: { $0.size < $1.size })?.path
    }

    private static func fileSize(_ path: String) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
