import Foundation

final class IntegrityChecker {
    private let process: ProcessRunner
    private let logger: HardenLogger

    init(process: ProcessRunner, logger: HardenLogger) {
        self.process = process
        self.logger = logger
    }

    func verifySelf(expectedTeamID: String) -> Bool {
        let path = CommandLine.arguments.first ?? ""
        guard !path.isEmpty else { return false }

        // Extract TeamIdentifier via codesign -dv (goes to stderr)
        let r = process.run("/usr/bin/codesign", ["-dv", "--verbose=4", path], timeoutSeconds: 10)
        let blob = (r.stderr + "\n" + r.stdout)

        guard let teamLine = blob.split(separator: "\n").first(where: { $0.contains("TeamIdentifier=") }) else {
            logger.error("codesign output did not contain TeamIdentifier.")
            return false
        }

        let parts = teamLine.split(separator: "=")
        let teamID = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if teamID != expectedTeamID {
            logger.error("TeamID mismatch: expected \(expectedTeamID), got \(teamID)")
            return false
        }

        // Optional: spctl assessment
        let s = process.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose", path], timeoutSeconds: 10)
        if s.exitCode != 0 {
            logger.error("spctl assessment failed: \(s.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return false
        }

        logger.info("Self integrity OK (TeamID \(teamID)).")
        return true
    }
}
