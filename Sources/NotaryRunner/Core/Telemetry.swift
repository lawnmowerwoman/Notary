import Foundation
import Darwin
import CoreWLAN

package struct TelemetrySnapshot: Sendable {
    package let sampledAt: Date
    package let cpu: TelemetryCPUUtilization?
    package let network: TelemetryNetworkTraffic?
    package let wireless: TelemetryWireless?

    package init(
        sampledAt: Date,
        cpu: TelemetryCPUUtilization?,
        network: TelemetryNetworkTraffic?,
        wireless: TelemetryWireless?
    ) {
        self.sampledAt = sampledAt
        self.cpu = cpu
        self.network = network
        self.wireless = wireless
    }
}

package struct TelemetrySamplingOptions: Sendable {
    package let wirelessReporting: TelemetryWirelessReportingMode

    package init(wirelessReporting: TelemetryWirelessReportingMode = .none) {
        self.wirelessReporting = wirelessReporting
    }
}

package enum TelemetryWirelessReportingMode: String, Codable, Sendable {
    case none
    case ssid
    case bssid

    package static func betaValue(from raw: Any?) -> TelemetryWirelessReportingMode {
        switch raw {
        case let value as Bool:
            return value ? .ssid : .none
        case let value as NSNumber:
            return value.boolValue ? .ssid : .none
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on", "ssid":
                return .ssid
            case "bssid":
                return .bssid
            default:
                return .none
            }
        default:
            return .none
        }
    }

    package var collectsWirelessDetails: Bool {
        self != .none
    }
}

package struct TelemetryWireless: Sendable {
    package let isConnected: Bool
    package let ssid: String?
    package let bssid: String?

    package init(isConnected: Bool, ssid: String?, bssid: String?) {
        self.isConnected = isConnected
        self.ssid = ssid
        self.bssid = bssid
    }

    package var connectionValue: String {
        guard isConnected else { return "Not connected" }
        return ssid?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Connected"
    }
}

package struct TelemetryCPUUtilization: Sendable {
    package let isPrimed: Bool
    package let activeFraction: Double
    package let userFraction: Double
    package let systemFraction: Double
    package let idleFraction: Double
    package let niceFraction: Double
    package let cores: [TelemetryCPUCoreUtilization]

    package init(
        isPrimed: Bool,
        activeFraction: Double,
        userFraction: Double,
        systemFraction: Double,
        idleFraction: Double,
        niceFraction: Double,
        cores: [TelemetryCPUCoreUtilization]
    ) {
        self.isPrimed = isPrimed
        self.activeFraction = activeFraction
        self.userFraction = userFraction
        self.systemFraction = systemFraction
        self.idleFraction = idleFraction
        self.niceFraction = niceFraction
        self.cores = cores
    }
}

package struct TelemetryCPUCoreUtilization: Sendable {
    package let index: Int
    package let activeFraction: Double
    package let userFraction: Double
    package let systemFraction: Double
    package let idleFraction: Double
    package let niceFraction: Double

    package init(
        index: Int,
        activeFraction: Double,
        userFraction: Double,
        systemFraction: Double,
        idleFraction: Double,
        niceFraction: Double
    ) {
        self.index = index
        self.activeFraction = activeFraction
        self.userFraction = userFraction
        self.systemFraction = systemFraction
        self.idleFraction = idleFraction
        self.niceFraction = niceFraction
    }
}

package struct TelemetryNetworkTraffic: Sendable {
    package let isPrimed: Bool
    package let uploadBytesPerSecond: Double
    package let downloadBytesPerSecond: Double
    package let totalBytesSent: UInt64
    package let totalBytesReceived: UInt64
    package let activeInterfaceCount: Int

    package init(
        isPrimed: Bool,
        uploadBytesPerSecond: Double,
        downloadBytesPerSecond: Double,
        totalBytesSent: UInt64,
        totalBytesReceived: UInt64,
        activeInterfaceCount: Int
    ) {
        self.isPrimed = isPrimed
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.activeInterfaceCount = activeInterfaceCount
    }
}

package protocol TelemetrySampling {
    func sample(at date: Date, options: TelemetrySamplingOptions) -> TelemetrySnapshot
}

package final class TelemetrySampler: TelemetrySampling, @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPUTicks: [CPUTicks] = []
    private var previousNetworkCounters: NetworkCounters?
    private let includeInactiveNetworkInterfaces: Bool

    package init(includeInactiveNetworkInterfaces: Bool = false) {
        self.includeInactiveNetworkInterfaces = includeInactiveNetworkInterfaces
    }

    package func sample(
        at date: Date = Date(),
        options: TelemetrySamplingOptions = TelemetrySamplingOptions()
    ) -> TelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }

        let cpu = sampleCPU()
        let network = sampleNetwork(at: date)
        let wireless = sampleWireless(mode: options.wirelessReporting)

        return TelemetrySnapshot(
            sampledAt: date,
            cpu: cpu,
            network: network,
            wireless: wireless
        )
    }

    package func reset() {
        lock.lock()
        previousCPUTicks = []
        previousNetworkCounters = nil
        lock.unlock()
    }

    private func sampleCPU() -> TelemetryCPUUtilization? {
        guard let currentTicks = CPUTicks.readCurrent() else {
            return nil
        }
        defer {
            previousCPUTicks = currentTicks
        }

        guard previousCPUTicks.count == currentTicks.count else {
            return TelemetryCPUUtilization.unprimed(coreCount: currentTicks.count)
        }

        let cores = currentTicks.enumerated().map { index, current in
            TelemetryCPUCoreUtilization(index: index, delta: current.delta(from: previousCPUTicks[index]))
        }
        return TelemetryCPUUtilization(cores: cores)
    }

    private func sampleNetwork(at date: Date) -> TelemetryNetworkTraffic? {
        guard let current = NetworkCounters.readCurrent(
            includeInactiveInterfaces: includeInactiveNetworkInterfaces,
            at: date
        ) else {
            return nil
        }
        defer {
            previousNetworkCounters = current
        }

        guard let previous = previousNetworkCounters else {
            return TelemetryNetworkTraffic(
                isPrimed: false,
                uploadBytesPerSecond: 0,
                downloadBytesPerSecond: 0,
                totalBytesSent: current.bytesSent,
                totalBytesReceived: current.bytesReceived,
                activeInterfaceCount: current.interfaceCount
            )
        }

        let elapsed = max(date.timeIntervalSince(previous.sampledAt), 0)
        guard elapsed > 0 else {
            return TelemetryNetworkTraffic(
                isPrimed: false,
                uploadBytesPerSecond: 0,
                downloadBytesPerSecond: 0,
                totalBytesSent: current.bytesSent,
                totalBytesReceived: current.bytesReceived,
                activeInterfaceCount: current.interfaceCount
            )
        }

        let sentDelta = current.bytesSent >= previous.bytesSent ? current.bytesSent - previous.bytesSent : 0
        let receivedDelta = current.bytesReceived >= previous.bytesReceived ? current.bytesReceived - previous.bytesReceived : 0

        return TelemetryNetworkTraffic(
            isPrimed: true,
            uploadBytesPerSecond: Double(sentDelta) / elapsed,
            downloadBytesPerSecond: Double(receivedDelta) / elapsed,
            totalBytesSent: current.bytesSent,
            totalBytesReceived: current.bytesReceived,
            activeInterfaceCount: current.interfaceCount
        )
    }

    private func sampleWireless(mode: TelemetryWirelessReportingMode) -> TelemetryWireless? {
        guard mode.collectsWirelessDetails else {
            return nil
        }

        guard let interface = CWWiFiClient.shared().interface() else {
            return TelemetryWireless(isConnected: false, ssid: nil, bssid: nil)
        }

        let ssid = interface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let bssid = mode == .bssid ? interface.bssid()?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        return TelemetryWireless(
            isConnected: ssid != nil || bssid != nil,
            ssid: ssid,
            bssid: bssid
        )
    }
}

private struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    static func readCurrent() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let status = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard status == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        return (0..<Int(cpuCount)).map { index in
            let base = index * Int(CPU_STATE_MAX)
            return CPUTicks(
                user: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
            )
        }
    }

    func delta(from previous: CPUTicks) -> CPUTicks {
        CPUTicks(
            user: user &- previous.user,
            system: system &- previous.system,
            idle: idle &- previous.idle,
            nice: nice &- previous.nice
        )
    }

    var total: UInt64 {
        user + system + idle + nice
    }
}

private struct NetworkCounters {
    let sampledAt: Date
    let bytesSent: UInt64
    let bytesReceived: UInt64
    let interfaceCount: Int

    static func readCurrent(includeInactiveInterfaces: Bool, at date: Date = Date()) -> NetworkCounters? {
        var sent: UInt64 = 0
        var received: UInt64 = 0
        var interfaceCount = 0
        var addressList: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addressList) == 0 else {
            return nil
        }
        defer {
            freeifaddrs(addressList)
        }

        var cursor = addressList
        while let current = cursor {
            let address = current.pointee
            defer {
                cursor = address.ifa_next
            }

            guard address.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = address.ifa_data else {
                continue
            }

            let name = String(cString: address.ifa_name)
            guard name != "lo0" else {
                continue
            }

            if !includeInactiveInterfaces {
                let flags = Int32(address.ifa_flags)
                guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else {
                    continue
                }
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            sent &+= UInt64(interfaceData.ifi_obytes)
            received &+= UInt64(interfaceData.ifi_ibytes)
            interfaceCount += 1
        }

        return NetworkCounters(
            sampledAt: date,
            bytesSent: sent,
            bytesReceived: received,
            interfaceCount: interfaceCount
        )
    }
}

private extension TelemetryCPUUtilization {
    init(cores: [TelemetryCPUCoreUtilization]) {
        let sums = cores.reduce(into: (active: 0.0, user: 0.0, system: 0.0, idle: 0.0, nice: 0.0)) { result, core in
            result.active += core.activeFraction
            result.user += core.userFraction
            result.system += core.systemFraction
            result.idle += core.idleFraction
            result.nice += core.niceFraction
        }
        let count = Double(max(cores.count, 1))
        self.init(
            isPrimed: true,
            activeFraction: sums.active / count,
            userFraction: sums.user / count,
            systemFraction: sums.system / count,
            idleFraction: sums.idle / count,
            niceFraction: sums.nice / count,
            cores: cores
        )
    }

    static func unprimed(coreCount: Int) -> TelemetryCPUUtilization {
        TelemetryCPUUtilization(
            isPrimed: false,
            activeFraction: 0,
            userFraction: 0,
            systemFraction: 0,
            idleFraction: 0,
            niceFraction: 0,
            cores: (0..<coreCount).map {
                TelemetryCPUCoreUtilization(
                    index: $0,
                    activeFraction: 0,
                    userFraction: 0,
                    systemFraction: 0,
                    idleFraction: 0,
                    niceFraction: 0
                )
            }
        )
    }
}

private extension TelemetryCPUCoreUtilization {
    init(index: Int, delta: CPUTicks) {
        let total = Double(delta.total)
        guard total > 0 else {
            self.init(
                index: index,
                activeFraction: 0,
                userFraction: 0,
                systemFraction: 0,
                idleFraction: 0,
                niceFraction: 0
            )
            return
        }

        let user = Double(delta.user) / total
        let system = Double(delta.system) / total
        let idle = Double(delta.idle) / total
        let nice = Double(delta.nice) / total

        self.init(
            index: index,
            activeFraction: user + system + nice,
            userFraction: user,
            systemFraction: system,
            idleFraction: idle,
            niceFraction: nice
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
