import Darwin
import Foundation

/// 本机芯片与性能核信息（设置页 CPU 卡展示）。
enum ResourceChipInfo {
    /// 如 `Apple Silicon M3 Max` / `Apple M4`。
    static let displayName: String = {
        let brand = sysctlString("machdep.cpu.brand_string")
        if brand.lowercased().hasPrefix("apple") {
            if brand.localizedCaseInsensitiveContains("silicon") {
                return brand
            }
            // `Apple M4` → `Apple Silicon M4`
            let rest = brand.dropFirst("Apple".count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? brand : "Apple Silicon \(rest)"
        }
        return brand.isEmpty ? "Apple Silicon" : brand
    }()

    /// 性能核物理核数（`hw.perflevel0`）；读不到则退回总物理核。
    static let performanceCoreCount: Int = {
        let p = sysctlInt("hw.perflevel0.physicalcpu")
        if p > 0 { return p }
        let total = sysctlInt("hw.physicalcpu")
        return max(1, total)
    }()

    static var performanceCoresLabel: String {
        L10n.ResourceMonitor.performanceCores(performanceCoreCount)
    }

    static func cpuFootnote(celsius: Double?) -> String {
        if let celsius {
            return L10n.ResourceMonitor.chipTemp(displayName, celsius)
        }
        return displayName
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }
}
