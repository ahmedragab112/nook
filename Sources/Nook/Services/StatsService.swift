import AppKit
import Combine
import Foundation

struct SystemSnapshot: Equatable {
    var cpu: Double = 0
    var cores: Int = 0
    var memoryUsed: Double = 0
    var memoryTotal: Double = 0
    var pressure: Double = 0
    var diskUsed: Double = 0
    var diskTotal: Double = 0
    var netUp: Double = 0
    var netDown: Double = 0
    var batteryPercent: Int? = nil
    var charging = false
    var uptime: TimeInterval = 0
    var load1: Double = 0
    var load2: Double = 0
    var load3: Double = 0
}

final class StatsService: ObservableObject {
    static let shared = StatsService()

    @Published var snapshot = SystemSnapshot()

    private var timer: Timer?
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: (inBytes: UInt64, outBytes: UInt64, at: Date)?
    private let batteryReader = BatteryReader()
    private var lastBattery: (percent: Int?, charging: Bool)?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }

    func sample() {
        var s = SystemSnapshot()
        s.cores = ProcessInfo.processInfo.processorCount
        s.cpu = cpuUsage()
        memory(&s)
        disk(&s)
        network(&s)
        batteryReader.sample()
        s.batteryPercent = batteryReader.percent
        s.charging = batteryReader.charging
        s.uptime = ProcessInfo.processInfo.systemUptime
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { s.load1 = loads[0]; s.load2 = loads[1]; s.load3 = loads[2] }
        handleCharging(previous: lastBattery, percent: s.batteryPercent, charging: s.charging)
        lastBattery = (s.batteryPercent, s.charging)
        snapshot = s
    }

    /// Pops a charging HUD the moment the cable goes in or out, with the
    /// current percentage. The compact notch keeps a small bolt otherwise.
    private func handleCharging(previous: (percent: Int?, charging: Bool)?, percent: Int?, charging: Bool) {
        guard let previous, let percent, previous.charging != charging else { return }
        guard AppSettings.shared.showChargingHUD else { return }
        let hud = HUDMessage(symbol: charging ? "bolt.fill" : "battery.50",
                             title: charging ? "Charging" : "On battery",
                             detail: "\(percent)%",
                             progress: Double(percent) / 100)
        NotchController.shared.show(hud: hud, duration: 2.2, respectSystemHUD: false)
    }

    private func cpuUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.cpu }
        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3
        defer { previousTicks = (user, system, idle, nice) }
        guard let previous = previousTicks else { return 0 }
        let du = Double(user &- previous.user)
        let ds = Double(system &- previous.system)
        let dn = Double(nice &- previous.nice)
        let di = Double(idle &- previous.idle)
        let busy = du + ds + dn
        let total = busy + di
        guard total > 0 else { return snapshot.cpu }
        return Util.rounded(busy / total * 100, 0)
    }

    private func memory(_ s: inout SystemSnapshot) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let pageSize = vm_kernel_page_size
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let active = Double(stats.active_count) * Double(pageSize)
        let wired = Double(stats.wire_count) * Double(pageSize)
        let compressed = Double(stats.compressor_page_count) * Double(pageSize)
        let purgeable = Double(stats.purgeable_count) * Double(pageSize)
        s.memoryUsed = (active + wired + compressed + purgeable) / 1_073_741_824
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &length, nil, 0)
        s.memoryTotal = Double(size) / 1_073_741_824
        s.pressure = s.memoryTotal > 0 ? Util.rounded(s.memoryUsed / s.memoryTotal * 100, 0) : 0
    }

    private func disk(_ s: inout SystemSnapshot) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) else { return }
        s.diskTotal = Double(values.volumeTotalCapacity ?? 0)
        s.diskUsed = s.diskTotal - Double(values.volumeAvailableCapacity ?? 0)
    }

    private func network(_ s: inout SystemSnapshot) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return }
        var totalIn = UInt64(0)
        var totalOut = UInt64(0)
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let name = String(cString: current.pointee.ifa_name)
            let isLoopback = flags & IFF_LOOPBACK != 0
            let running = flags & IFF_RUNNING != 0
            if !isLoopback, running, (name.hasPrefix("en") || name.hasPrefix("ap") || name.hasPrefix("bridge")),
               let data = current.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(counters.ifi_ibytes)
                totalOut += UInt64(counters.ifi_obytes)
            }
            pointer = current.pointee.ifa_next
        }
        freeifaddrs(addrs)
        let now = Date()
        defer { previousNet = (totalIn, totalOut, now) }
        guard let previous = previousNet else { return }
        let dt = max(0.1, now.timeIntervalSince(previous.at))
        let dIn = totalIn >= previous.inBytes ? Double(totalIn - previous.inBytes) : Double(UInt64(1 << 32) + totalIn - previous.inBytes)
        let dOut = totalOut >= previous.outBytes ? Double(totalOut - previous.outBytes) : Double(UInt64(1 << 32) + totalOut - previous.outBytes)
        s.netDown = dIn / dt / 1_048_576
        s.netUp = dOut / dt / 1_048_576
    }
}

