import Darwin
import Foundation
import IOKit

/// 经私有 `AppleSMC` 读 CPU 温度（与 Stats / iStat 同类路径）。
/// 无公开 API、各代 Apple Silicon key 不同；读失败返回 nil，UI 只显示芯片名。
/// 不需要 root；App 未开沙盒即可。
enum ResourceCPUTemperature {
    private static let lock = NSLock()
    private static var connection: io_connect_t = 0
    private static var connected = false
    private static var loggedOnce = false
    /// 上次命中的 key，优先再读，减少枚举。
    private static var hotKeys: [String] = []

    /// 当前 CPU 温度（℃）；不可用则为 nil。
    static func celsius() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        ensureConnected()
        guard connected else {
            logOnce(ok: false, detail: "SMC 未连接")
            return nil
        }

        if !hotKeys.isEmpty {
            let samples = hotKeys.compactMap { readKeyUnlocked($0) }.filter(isPlausible)
            if let avg = average(samples) {
                logOnce(ok: true, detail: "hot=\(hotKeys.joined(separator: ",")) temp=\(String(format: "%.1f", avg))")
                return avg
            }
            hotKeys = []
        }

        // Intel 常见单点 key。
        for key in Self.intelKeys {
            if let value = readKeyUnlocked(key), isPlausible(value) {
                hotKeys = [key]
                logOnce(ok: true, detail: "intel=\(key) temp=\(String(format: "%.1f", value))")
                return value
            }
        }

        // Apple Silicon：对各代候选 key 取均值（无则跳过）。
        var samples: [(String, Double)] = []
        for key in Self.appleSiliconKeys {
            guard let value = readKeyUnlocked(key), isPlausible(value) else { continue }
            samples.append((key, value))
            if samples.count >= 12 { break }
        }
        // 去掉相对中位数偏离过大的点，避免个别 key 拉低均值。
        let filtered = filterOutliers(samples.map(\.1))
        guard let avg = average(filtered) else {
            logOnce(ok: false, detail: "无可用温度 key")
            return nil
        }
        let median = filtered.sorted()[filtered.count / 2]
        hotKeys = samples.filter { abs($0.1 - median) <= 15 }.map(\.0)
        if hotKeys.isEmpty { hotKeys = samples.prefix(4).map(\.0) }
        logOnce(ok: true, detail: "avg keys=\(hotKeys.count) temp=\(String(format: "%.1f", avg))")
        return avg
    }

    private static func filterOutliers(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let kept = values.filter { abs($0 - median) <= 15 }
        return kept.isEmpty ? values : kept
    }

    // MARK: - Connection

    private static func ensureConnected() {
        guard !connected else { return }
        let names = ["AppleSMC", "AppleSMCKeysEndpoint"]
        for name in names {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            guard service != 0 else { continue }
            var conn: io_connect_t = 0
            let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
            IOObjectRelease(service)
            if kr == KERN_SUCCESS {
                connection = conn
                connected = true
                return
            }
        }
    }

    private static func logOnce(ok: Bool, detail: String) {
        guard !loggedOnce else { return }
        loggedOnce = true
        if ok {
            AppLog.info("ResourceMonitor", "SMC 温度可读", ["detail": detail])
        } else {
            AppLog.warn("ResourceMonitor", "SMC 温度不可用", ["detail": detail])
        }
    }

    // MARK: - Read / decode

    private static func readKeyUnlocked(_ key: String) -> Double? {
        guard connected, key.utf8.count == 4 else { return nil }
        guard let info = keyInfo(key) else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = SMCCommand.readBytes
        input.keyInfo.dataSize = info.size

        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            SMCCommand.kernelIndex,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard kr == KERN_SUCCESS else { return nil }
        return decode(bytes: output.bytes, type: info.type, size: info.size)
    }

    private static func keyInfo(_ key: String) -> (type: UInt32, size: UInt32)? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            SMCCommand.kernelIndex,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard kr == KERN_SUCCESS, output.keyInfo.dataSize > 0 else { return nil }
        return (output.keyInfo.dataType, output.keyInfo.dataSize)
    }

    private static func decode(
        bytes: SMCBytes,
        type: UInt32,
        size: UInt32
    ) -> Double? {
        let typeStr = fourCharString(type)
        let b0 = bytes.0
        let b1 = bytes.1
        let b2 = bytes.2
        let b3 = bytes.3

        switch typeStr {
        case "sp78", "sp87":
            // 大端 signed fixed-point（7.8 / 8.7 近似：整字节 + 小数/256）。
            let value = Double(Int8(bitPattern: b0)) + Double(b1) / 256.0
            return value
        case "sp5a":
            let raw = Int16(b0) << 8 | Int16(b1)
            return Double(raw) / 1024.0
        case "sp69":
            let raw = Int16(b0) << 8 | Int16(b1)
            return Double(raw) / 512.0
        case "fpe2":
            let raw = UInt16(b0) << 8 | UInt16(b1)
            return Double(raw) / 4.0
        case "flt ", "flt":
            // `flt ` 在本机为小端 IEEE754；先 LE。大端常得到「看似合理」的错值（如 72℃→21℃）。
            let le = Float(bitPattern: UInt32(b3) << 24 | UInt32(b2) << 16 | UInt32(b1) << 8 | UInt32(b0))
            if isPlausible(Double(le)) { return Double(le) }
            let be = Float(bitPattern: UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3))
            if isPlausible(Double(be)) { return Double(be) }
            return nil
        default:
            guard size >= 2 else { return nil }
            let value = Double(Int8(bitPattern: b0)) + Double(b1) / 256.0
            return isPlausible(value) ? value : nil
        }
    }

    private static func isPlausible(_ value: Double) -> Bool {
        value >= 10 && value <= 110
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, byte) in key.utf8.enumerated() where i < 4 {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private static func fourCharString(_ code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }

    // MARK: - Key catalogs（来自 Stats / 社区观测，无官方保证）

    private static let intelKeys = ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H", "TCAD"]

    /// M1…M5 候选并集；读不到的 key 会被跳过。
    private static let appleSiliconKeys: [String] = [
        // M1
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        // M2
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        // M3
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        // M4
        "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",
        // M5
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R",
        "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]
}

// MARK: - SMC wire types（社区约定布局）

private enum SMCCommand {
    static let kernelIndex: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}
