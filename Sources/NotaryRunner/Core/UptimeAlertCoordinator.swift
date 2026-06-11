import Foundation
import ApplicationServices

package enum UptimeAlertSeverity: String {
    case recommendation
    case required
}

package struct UptimeAlertPayload {
    package let severity: UptimeAlertSeverity
    package let title: String
    package let message: String

    package init(severity: UptimeAlertSeverity, title: String, message: String) {
        self.severity = severity
        self.title = title
        self.message = message
    }
}

package enum UptimeAlertCoordinator {
    package static let cooldown: TimeInterval = 24 * 60 * 60

    package static func handleIfNeeded(
        execution: RunnerExecution,
        state: inout RunnerState,
        logger: HardenLogger
    ) {
        guard let run = execution.runs.first(where: { $0.spec.section == "System" && $0.spec.key == "CheckSystemUptime" }) else {
            return
        }

        guard run.result.status == .fail else { return }

        if let lastPromptAt = state.lastUptimePromptAt,
           Date().timeIntervalSince(lastPromptAt) < cooldown {
            logger.info("[UptimeAlert] Cooldown active; skipping user notification.")
            return
        }

        if isScreenSharingActive(logger: logger) {
            logger.info("[UptimeAlert] Screen sharing detected; deferring user notification.")
            return
        }

        if isFullscreenAppActive(logger: logger) {
            logger.info("[UptimeAlert] Full-screen activity detected; deferring user notification.")
            return
        }

        guard let payload = payload(for: run.result) else { return }
        guard launchAlertApp(payload: payload, logger: logger) else { return }

        state.lastUptimePromptAt = Date()
        logger.info("[UptimeAlert] User notification opened.")
    }

    private static func payload(for result: CheckResult) -> UptimeAlertPayload? {
        let severity: UptimeAlertSeverity = (result.severity == .high) ? .required : .recommendation

        switch severity {
        case .recommendation:
            return UptimeAlertPayload(
                severity: severity,
                title: "Reboot Recommended",
                message: """
                Notary detected that this Mac has been running longer than the recommended uptime threshold.

                \(result.details)

                Please save your work and restart the Mac at a convenient time.
                """
            )
        case .required:
            return UptimeAlertPayload(
                severity: severity,
                title: "Reboot Required",
                message: """
                Notary detected that this Mac exceeded the maximum allowed uptime threshold.

                \(result.details)

                Please restart the Mac as soon as possible to avoid compliance issues.
                """
            )
        }
    }

    private static func launchAlertApp(payload: UptimeAlertPayload, logger: HardenLogger) -> Bool {
        guard let info = ManagedPrefs.consoleUserInfo() else {
            logger.info("[UptimeAlert] No console user session available; skipping user notification.")
            return false
        }

        let appBundle = "/Applications/Notary.app"
        guard FileManager.default.fileExists(atPath: appBundle) else {
            logger.warn("[UptimeAlert] Notary.app not found at \(appBundle)")
            return false
        }

        let args = [
            "asuser", "\(info.uid)",
            "/usr/bin/open",
            "-n",
            appBundle,
            "--args",
            "--uptime-alert",
            "--uptime-severity", payload.severity.rawValue,
            "--uptime-title", payload.title,
            "--uptime-message", payload.message
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        do {
            try process.run()
        } catch {
            logger.warn("[UptimeAlert] Failed to launch Notary uptime alert app: \(error)")
            return false
        }

        return true
    }

    private static func isScreenSharingActive(logger: HardenLogger) -> Bool {
        let checks: [(name: String, args: [String])] = [
            ("screensharingagent", ["-x", "screensharingagent"]),
            ("screensharingd", ["-x", "screensharingd"])
        ]

        for check in checks {
            if let result = try? Shell.run("/usr/bin/pgrep", check.args, timeout: 2, logger: logger),
               result.code == 0,
               !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.develop("[UptimeAlert] Active screen-sharing process detected: \(check.name)")
                return true
            }
        }

        return false
    }

    private static func isFullscreenAppActive(logger: HardenLogger) -> Bool {
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let widthThreshold = screenBounds.width * 0.95
        let heightThreshold = screenBounds.height * 0.95

        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let ignoredOwners: Set<String> = ["Window Server", "Dock", "Control Center", "NotificationCenter"]

        for info in infoList {
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            if ignoredOwners.contains(owner) { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer > 1 { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.01 { continue }

            guard let boundsObject = info[kCGWindowBounds as String] else {
                continue
            }

            guard let boundsDict = boundsObject as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            if bounds.width >= widthThreshold && bounds.height >= heightThreshold {
                logger.develop("[UptimeAlert] Full-screen candidate detected: owner=\(owner) size=\(Int(bounds.width))x\(Int(bounds.height))")
                return true
            }
        }

        return false
    }
}
