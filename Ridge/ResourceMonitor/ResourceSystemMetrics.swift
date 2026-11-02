import Darwin
import Foundation

/// 系统级 RAM / Swap / CPU；温度单独探测。
enum ResourceSystemMetrics {
    struct MemoryInfo {
        var usedBytes: UInt64
        var totalBytes: UInt64
        var swapUsedBytes: UInt64
        var swapTotalBytes: UInt64
    }

    struct CPUSample {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    static func memory() -> MemoryInfo {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        var used: UInt64 = 0
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let active = UInt64(stats.active_count) * page
            let inactive = UInt64(stats.inactive_count) * page
            let wired = UInt64(stats.wire_count) * page
            let compressed = UInt64(stats.compressor_page_count) * page
            used = active + inactive + wired + compressed
            used = min(used, total)
        }
        let swap = swapUsage()
        return MemoryInfo(
            usedBytes: used,
            totalBytes: total,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total
        )
    }

    static func cpuSample() -> CPUSample? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUSample(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    static func cpuPercent(previous: CPUSample?, current: CPUSample) -> Double {
        guard let previous else { return 0 }
        let user = Double(current.user &- previous.user)
        let system = Double(current.system &- previous.system)
        let idle = Double(current.idle &- previous.idle)
        let nice = Double(current.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return ((user + system + nice) / total) * 100
    }

    private struct SwapUsage {
        var xsu_total: UInt64 = 0
        var xsu_avail: UInt64 = 0
        var xsu_used: UInt64 = 0
        var xsu_pagesize: UInt32 = 0
        var xsu_encrypted: UInt32 = 0
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }
}
