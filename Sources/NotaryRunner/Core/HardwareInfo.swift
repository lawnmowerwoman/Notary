import Foundation
import IOKit

package enum HardwareInfo {

    package enum FormFactor: Equatable {
        case notebook
        case desktop
        case unknown
    }

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

    package static func ioPlatformUUID() -> String? {
        guard let r = try? Shell.run(
            "/usr/sbin/ioreg",
            ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeout: 5
        ) else { return nil }

        for line in r.stdout.split(separator: "\n") {
            if line.contains("IOPlatformUUID") {
                let parts = line.split(separator: "\"")
                if let uuid = parts.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                   !uuid.contains("IOPlatformUUID") {
                    return String(uuid).trimmingCharacters(in: .whitespacesAndNewlines)
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
        formFactor() == .notebook
    }

    package static func isDesktopMac() -> Bool {
        formFactor() == .desktop
    }

    package static func formFactor() -> FormFactor {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return classifyFormFactor(model: hwModel(), hasBuiltInLid: nil)
        }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else {
            return classifyFormFactor(model: hwModel(), hasBuiltInLid: nil)
        }
        // Presence identifies the built-in lid; its value only says open/closed.
        return classifyFormFactor(model: hwModel(), hasBuiltInLid: values["AppleClamshellState"] != nil)
    }

    package static func classifyFormFactor(model: String?, hasBuiltInLid: Bool?) -> FormFactor {
        if hasBuiltInLid == true || model?.hasPrefix("MacBook") == true { return .notebook }
        if hasBuiltInLid == false { return .desktop }
        if let model, ["iMac", "Macmini", "MacPro", "MacStudio", "Xserve"].contains(where: { model.hasPrefix($0) }) {
            return .desktop
        }
        return .unknown
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
