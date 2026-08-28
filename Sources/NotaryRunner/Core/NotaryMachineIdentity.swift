import CryptoKit
import Foundation

package enum NotaryMachineIdentity {
    package static let salt = "MinistryOfCode.Notary.Licensing.MachineIdentifier.v1"

    package static func current() -> String? {
        guard let platformUUID = HardwareInfo.ioPlatformUUID() else {
            return nil
        }
        return identifier(forIOPlatformUUID: platformUUID)
    }

    package static func identifier(forIOPlatformUUID platformUUID: String) -> String? {
        let normalized = platformUUID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }
        return sha256Hex("\(salt):\(normalized)")
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
