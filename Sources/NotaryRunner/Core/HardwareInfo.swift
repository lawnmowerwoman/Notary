import Foundation
import IOKit

package enum HardwareInfo {

    package static func serialNumber() -> String? {
        guard let r = try? Shell.run(
            "/usr/sbin/ioreg",
            ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeout: 5
        ) else { return nil }

        for line in r.stdout.split(separator: "\n") {
            if line.contains("IOPlatformSerialNumber") {
                let parts = line.split(separator: "\"")
                if let serial = parts.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                   !serial.contains("IOPlatformSerialNumber") {
                    return String(serial).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    package static func hwModel() -> String? {
        guard let r = try? Shell.run(
            "/usr/sbin/sysctl",
            ["-n", "hw.model"],
            timeout: 5
        ) else { return nil }

        let model = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
    }

    package static func isMobileMac() -> Bool {
        guard let model = hwModel() else { return false }
        return model.hasPrefix("MacBook")
    }

    package static func isDesktopMac() -> Bool {
        return !isMobileMac()
    }

    package static func isAppleSilicon() -> Bool {
        guard let r = try? Shell.run(
            "/usr/sbin/sysctl",
            ["-n", "hw.optional.arm64"],
            timeout: 5
        ) else { return false }

        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    package static func isIntel() -> Bool {
        return !isAppleSilicon()
    }
}
