import Foundation


package struct RunnerCapabilities {
    package let isRoot: Bool

    // Für später praktisch (nur Beispiele)
    package let canRunSystemsetup: Bool
    package let canRunLaunchctl: Bool

    package let signing: SigningInfo?

    package struct SigningInfo: Codable {
        package let identifier: String?
        package let teamIdentifier: String?
        package let designatedRequirement: String?
    }


    package static func detect(logger: HardenLogger) -> RunnerCapabilities {
        let isRoot = (geteuid() == 0)

        let canRunSystemsetup = FileManager.default.isExecutableFile(atPath: "/usr/sbin/systemsetup")
        let canRunLaunchctl   = FileManager.default.isExecutableFile(atPath: "/bin/launchctl")

        let signing = detectSigning(logger: logger)

        let caps = RunnerCapabilities(
            isRoot: isRoot,
            canRunSystemsetup: canRunSystemsetup,
            canRunLaunchctl: canRunLaunchctl,
            signing: signing
        )

        return caps
    }


    private static func detectSigning(logger: HardenLogger) -> SigningInfo? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else {
            logger.develop("[CAP] codesign not available; cannot detect signing info")
            return nil
        }

        let exePath = (CommandLine.arguments.first ?? "")
        if exePath.isEmpty {
            logger.develop("[CAP] cannot detect executable path (argv[0] empty)")
            return nil
        }

        // codesign -dv writes to stderr
        let r = try? Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", exePath], timeout: 10)
        guard let r else {
            logger.develop("[CAP] codesign -dv failed to execute")
            return nil
        }

        let text = [r.stdout, r.stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        func extract(_ key: String) -> String? {
            // Matches "Identifier=..." etc.
            for line in text.split(separator: "\n") {
                if line.hasPrefix(key) {
                    return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        let identifier = extract("Identifier=")
        let team = extract("TeamIdentifier=")

        // Designated requirement is a separate command; optional but useful.
        let dr = try? Shell.run("/usr/bin/codesign", ["-dr", "-", exePath], timeout: 10)
        let drText = [dr?.stdout ?? "", dr?.stderr ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        let designated = drText.isEmpty ? nil : drText.trimmingCharacters(in: .whitespacesAndNewlines)

        let info = SigningInfo(identifier: identifier, teamIdentifier: team, designatedRequirement: designated)

        // logger.info("[CAP] signing identifier=\(identifier ?? "nil") team=\(team ?? "nil")")
        return info
    }
}
