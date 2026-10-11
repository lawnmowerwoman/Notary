import Foundation
import NotaryCore

enum SecurePlistProtectionTests {
    static func run() {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let plist = root.appendingPathComponent("notary.plist")
            let store = SecurePlistStore<RunnerState>(rootURL: plist, tmpURL: plist)
            try store.enforceSecurityIfPresent()
            expect(!FileManager.default.fileExists(atPath: plist.path), "migration does not create missing state")

            let original = try PropertyListSerialization.data(fromPropertyList: ["activationCode": "NOTXTEST", "apptoken": "disposable-token"], format: .binary, options: 0)
            try original.write(to: plist, options: [.completeFileProtectionUnlessOpen])
            try store.enforceSecurityIfPresent()
            expect(try Data(contentsOf: plist) == original, "migration preserves exact state bytes")
            try expectProtection(plist)
            expect(try store.load()?.activationCode == "NOTXTEST", "migrated state remains readable")

            try store.save(RunnerState())
            try expectProtection(plist)
            try store.merge(values: ["activationCode": "NOTXMERGED"])
            try expectProtection(plist)
            expect(try store.load()?.activationCode == "NOTXMERGED", "secure merge remains readable")

            try ReconEAStore(path: plist.path).write(values: ["Notary Compliance": "compliant"])
            try expectProtection(plist)
            let values = try store.readValues(keys: ["activationCode", "Notary Compliance"])
            expect(values["activationCode"] as? String == "NOTXMERGED", "EA writer retains state")
            expect(values["Notary Compliance"] as? String == "compliant", "EA writer retains output")

            try Data("not a plist".utf8).write(to: plist)
            do {
                _ = try store.load()
                fatalError("Corrupt plist unexpectedly loaded")
            } catch {
                expect(String(describing: error).hasPrefix("Decode failed:"), "corrupt data is a decode error")
            }

            try FileManager.default.removeItem(at: plist)
            try FileManager.default.createDirectory(at: plist, withIntermediateDirectories: false)
            do {
                _ = try store.load()
                fatalError("Unreadable path unexpectedly loaded")
            } catch {
                expect(String(describing: error).hasPrefix("Read failed:"), "inaccessible path is a read error")
            }
        } catch { fatalError("Secure plist protection tests failed: \(error)") }
    }

    private static func expectProtection(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        expect(attributes[.protectionKey] as? String == FileProtectionType.completeUntilFirstUserAuthentication.rawValue,
               "state uses background-compatible Class C")
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "state remains private 0600")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError("Test failed: \(message)") }
    }
}
