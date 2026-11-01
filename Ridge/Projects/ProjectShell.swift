import Foundation

/// 轻量外部命令封装（lsof / ps / docker）。
enum ProjectShell {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval = 4
    ) -> Result {
        // 用临时文件承接输出，避免 Pipe 缓冲区塞满后子进程写阻塞、父进程干等超时（ps -axww 尤其容易）。
        let fm = FileManager.default
        let stamp = UUID().uuidString
        let outURL = fm.temporaryDirectory.appendingPathComponent("ridge-shell-\(stamp).out")
        let errURL = fm.temporaryDirectory.appendingPathComponent("ridge-shell-\(stamp).err")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        guard
            let outHandle = try? FileHandle(forWritingTo: outURL),
            let errHandle = try? FileHandle(forWritingTo: errURL)
        else {
            return Result(exitCode: -1, stdout: "", stderr: "无法创建临时输出文件")
        }
        process.standardOutput = outHandle
        process.standardError = errHandle

        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + timeout)
        if process.isRunning {
            process.terminate()
            try? outHandle.close()
            try? errHandle.close()
            AppLog.warn("Projects", "命令超时已终止", [
                "bin": launchPath,
                "args": arguments.prefix(4).joined(separator: " ")
            ])
            return Result(exitCode: -1, stdout: "", stderr: "timeout")
        }

        try? outHandle.close()
        try? errHandle.close()
        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func which(_ name: String) -> String? {
        let result = run("/usr/bin/which", arguments: [name], timeout: 2)
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
