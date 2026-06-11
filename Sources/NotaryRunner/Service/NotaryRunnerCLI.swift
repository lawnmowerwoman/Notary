import Foundation
import ArgumentParser
import NotaryCore

@main

struct NotaryRunner: AsyncParsableCommand {
    // MARK: Debuglevel Helper
    private static func resolveDebugLevel(
        argv: [String],
        verboseFlag: Bool,
        developFlag: Bool
    ) -> Int {
        if developFlag { return 2 }

        // Count literal -v and compact short-option clusters like -vv
        var vCount = 0

        for arg in argv.dropFirst() {
            if arg == "--develop" {
                return 2
            }

            if arg == "-v" {
                vCount += 1
                continue
            }

            // Handle grouped short flags, e.g. -vv
            if arg.hasPrefix("-"), !arg.hasPrefix("--"), arg.count > 2 {
                let shortFlags = arg.dropFirst()
                let onlyVs = shortFlags.allSatisfy { $0 == "v" }
                if onlyVs {
                    vCount += shortFlags.count
                }
            }
        }

        // Fallback: if parser saw --verbose but raw scan found no compact -v,
        // still honor it as level 1.
        if vCount == 0, verboseFlag {
            vCount = 1
        }

        return min(vCount, 2)
    }

    // MARK: Flags and Options
    static let configuration = CommandConfiguration(
        commandName: "notary",
        abstract: "Compliance check + remediation runner for macOS hardening.",
        version: NotaryVersion.marketingVersion
    )

    @Flag(help: "Dump raw effective managed config and exit.")
    var dumpConfig: Bool = false

    @Flag(help: "Dump config with Pentabool-resolved values and exit.")
    var dumpResolved: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose logging.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable develop logging (same as -vv).")
    var develop: Bool = false

    @Flag(help: "Run as long-lived engagement service with main loop.")
    var engagement: Bool = false

    @Option(help: "Engagement interval in seconds (default: 3600).")
    var engagementInterval: Int = 3600

    @Flag(help: "Force one-shot runner mode, even in a console session.")
    var run: Bool = false

    @Flag(help: "Deprecated. Open /Applications/Notary.app for the report UI.")
    var report: Bool = false

    @Flag(help: "Deprecated. Open /Applications/Notary.app --config for the configurator.")
    var config: Bool = false

    @Option(help: "Preferences domain to read (default: de.twocent.notary).")
    var domain: String = "de.twocent.notary"

    // MARK: run()

    func run() async throws {
        // ---------------------------------------------------------------------
        // ✨ TwoCent Labs Notary Runner – Main Execution Entry
        // ---------------------------------------------------------------------
        // 1. Initialize logging
        // 2. Load effective configuration via CFPreferences
        // 3. Resolve Pentabool modes
        // 4. Execute compliance checks
        // 5. Update Jamf Extension Attributes
        // 6. Exit with structured result
        //
        // This runner replaces the legacy shell implementation and is designed
        // to provide structured logging, strong typing and better maintainability.
        // ---------------------------------------------------------------------

        let debugLevel = Self.resolveDebugLevel(
            argv: CommandLine.arguments,
            verboseFlag: verbose,
            developFlag: develop
        )

        let logger = HardenLogger(debugLevel: debugLevel, scriptName: "notary")

        if config || report {
            logger.warn("GUI entry points moved to /Applications/Notary.app")
            return
        }

        logger.start("Notary Trust Verification started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion), debug=\(debugLevel))")

        if !engagement {
            let caps = RunnerCapabilities.detect(logger: logger)

            if let s = caps.signing {
                logger.debug("[CAP] isRoot=\(caps.isRoot) id=\(s.identifier ?? "?") team=\(s.teamIdentifier ?? "?")")
            } else {
                logger.debug("[CAP] isRoot=\(caps.isRoot) signing=unknown")
            }
        }

        if engagement {
            let interval = max(1, engagementInterval)
            let service = EngagementService(logger: logger, domain: domain, interval: TimeInterval(interval))
            let signals = ProcessSignalObserver(
                logger: logger,
                onTerminate: { _ in
                    service.stop()
                },
                onReload: {
                    service.requestReload(reason: "SIGHUP reload request")
                }
            )
            signals.startObserving()
            service.runForever()
            signals.stopObserving()
            return
        }

        // ---------------------------------------------------------------------
        // MARK: Config + Dump
        // ---------------------------------------------------------------------

        if dumpConfig || dumpResolved {
            let configurationSnapshot = ManagedConfigLoader.load(domain: domain, logger: logger)
            let rawSnapshot = configurationSnapshot.rawSnapshot
            let managed = configurationSnapshot.config
            // NOTE: `managed` is currently only used for dump output here;
            // normal execution receives the resolved config via ManagedConfigLoader.
            _ = managed

            var output: [String: Any] = ["domain": domain, "raw": rawSnapshot]

            if dumpResolved {
                let modeKeys = GeneratedKeys.modeKeys
                let parameterKeys = GeneratedKeys.parameterKeys

                var resolved: [String: Any] = [:]

                func resolve(fullKey: String, value: Any) -> Any {
                    if modeKeys.contains(fullKey) { return toPentabool(value).rawValue }
                    if parameterKeys.contains(fullKey) { return value }
                    return value
                }

                for (section, value) in rawSnapshot {
                    if let dict = value as? [String: Any] {
                        for (k, v) in dict {
                            let fk = "\(section).\(k)"
                            resolved[fk] = resolve(fullKey: fk, value: v)
                        }
                    } else {
                        resolved[section] = value
                    }
                }

                output["resolved"] = resolved
                output["note"] = "resolved: modeKeys => pentabool (-2..2); parameterKeys/unknown => raw"

                output["normalizedParameters"] = [
                    "Org.OrgName": managed.orgName,
                    "Org.OrgContact": managed.orgContact,
                    "LoginWindow.SudoTimeout": managed.sudoTimeout,
                    "ScreenSaver.ScreenSaverDelay": managed.screenSaverDelay,
                    "TimeNTP.ForceTimeServer": managed.forceTimeServer,
                    "TimeNTP.TimeServer": managed.timeServer as Any,
                    "TimeNTP.DefaultTimeZone": managed.defaultTimeZone as Any
                ]

            }

            print(ManagedPrefs.toPrettyJSON(output))
            //Foundation.exit(0)
            return
        }

        let caps = RunnerCapabilities.detect(logger: logger)
        logger.info("Runtime mode – executing checks")
        try await NotaryCycleExecutor.execute(domain: domain, logger: logger, caps: caps)
    }
}
