import Foundation
import NotaryCore

@main
enum NotaryAppMain {
    @MainActor
    static func main() {
        let logger = HardenLogger(debugLevel: resolvedDebugLevel(), scriptName: "NotaryApp")

        if let alertPayload = parseUptimeAlertPayload() {
            logger.start("NotaryGUI uptime alert started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion))")
            NotaryGUI.showUptimeAlertWindow(logger: logger, payload: alertPayload)
            return
        }

        if CommandLine.arguments.contains("--config") {
            logger.start("NotaryConfigurator placeholder started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion))")
            NotaryGUI.showConfiguratorPlaceholder()
            return
        }

        if CommandLine.arguments.contains("--reporter") || CommandLine.arguments.contains("--jamf-reporter") {
            logger.start("NotaryReporter started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion))")
            NotaryGUI.showJamfReporterWindow(logger: logger)
            return
        }

        logger.start("NotaryGUI report started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion))")
        NotaryGUI.showReportWindow(logger: logger)
    }

    private static func resolvedDebugLevel() -> Int {
        if CommandLine.arguments.contains("--develop") {
            return 2
        }
        return min(CommandLine.arguments.filter { $0 == "-v" || $0 == "--verbose" }.count, 2)
    }

    private static func parseUptimeAlertPayload() -> UptimeAlertPayload? {
        guard CommandLine.arguments.contains("--uptime-alert") else { return nil }

        func value(after flag: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
            let next = CommandLine.arguments.index(after: index)
            guard next < CommandLine.arguments.endIndex else { return nil }
            return CommandLine.arguments[next]
        }

        let severity = UptimeAlertSeverity(rawValue: value(after: "--uptime-severity") ?? "") ?? .recommendation
        let title = value(after: "--uptime-title") ?? (severity == .required ? "Reboot Required" : "Reboot Recommended")
        let message = value(after: "--uptime-message") ?? "Notary recommends a reboot."
        return UptimeAlertPayload(severity: severity, title: title, message: message)
    }
}
