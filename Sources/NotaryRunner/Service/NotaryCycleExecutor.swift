import Foundation
import NotaryCore

enum NotaryCycleExecutor {
    static let transporterHeartbeatInterval: TimeInterval = 60 * 60
    static let managedConfigGraceInterval: TimeInterval = 5 * 60

    static func execute(
        domain: String,
        logger: HardenLogger,
        caps: RunnerCapabilities,
        engagementMode: Bool = false
    ) async throws {
        try guardNotShuttingDown(logger: logger, phase: "cycle start")

        let store = SecurePlistStore<RunnerState>(logger: logger)
        var state = try store.load() ?? RunnerState()

        let configuredAPIUpdate = state.apiupdate ?? true
        let configuredReportPercent = state.reportpercent ?? false
        var effectiveReportPercent = configuredReportPercent
        var effectiveAPIUpdate = configuredAPIUpdate

        let clientID = state.jamfClientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientSecret = state.jamfClientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if clientID.isEmpty || clientSecret.isEmpty {
            logger.info("Jamf API credentials missing; EA update skipped for this run.")
            effectiveAPIUpdate = false
        }

        guard let serial = HardwareInfo.serialNumber() else {
            logger.fatal(902, "Unable to determine local serial number")
        }
        logger.info("Local serial number detected: \(serial)")
        let hardwareModel = HardwareInfo.hwModel()

        try guardNotShuttingDown(logger: logger, phase: "configuration load")
        let configurationSnapshot = ManagedConfigLoader.load(domain: domain, logger: logger)
        if try deferForTransientManagedConfigGapIfNeeded(
            configurationSnapshot: configurationSnapshot,
            state: &state,
            store: store,
            logger: logger
        ) {
            return
        }
        if engagementMode {
            AirDropAutoDisableCoordinator.handleIfNeeded(
                config: configurationSnapshot.config,
                state: &state,
                logger: logger
            )
        }
        let execution = try RunnerEngine.execute(
            rawSnapshot: configurationSnapshot.rawSnapshot,
            config: configurationSnapshot.config,
            logger: logger,
            caps: caps,
            lastKnownPassingChecks: state.lastKnownPassingChecks
        )
        let proof = execution.proof

        try guardNotShuttingDown(logger: logger, phase: "proof generation")

        logger.info("Checks: \(proof.countsBlock)")
        if proof.compliant {
            logger.info("Compliance: PASSED")
        } else {
            logger.warn("Compliance: FAILED (\(proof.hardFailCount) critical findings)")
        }

        let transportDecision = Transporter.decide(
            proof: proof,
            state: state,
            at: proof.generatedAt,
            heartbeatInterval: transporterHeartbeatInterval,
            reportPercent: effectiveReportPercent
        )
        var shouldTransport = transportDecision.shouldUpdate
        var transportReason = transportDecision.reason

        let jamfProURL = JamfLocalConfig.jamfProURL()
        if let jamfProURL {
            logger.info("Jamf Pro URL detected: \(jamfProURL.absoluteString)")
        } else {
            logger.info("Jamf unavailable right now; EA update skipped for this run.")
            effectiveAPIUpdate = false
        }

        try guardNotShuttingDown(logger: logger, phase: "pre-transport")

        if effectiveAPIUpdate, let jamfProURL {
            var idsByName: [String: Int] = [:]
            var computerID: Int? = state.computerID

            let http = HTTPClient(logger: logger)
            logger.develop("[HTTP] config: \(http.configDescription)")

            let creds: JamfCredentialsProvider = { (clientID: clientID, clientSecret: clientSecret) }
            let auth = JamfAuth(
                logger: logger,
                http: http,
                baseURL: jamfProURL,
                credentials: creds,
                initialBearerToken: state.jamfBearerToken,
                initialBearerExpirationEpoch: state.jamfBearerExpirationEpoch
            )

            let api = JamfAPI(logger: logger, http: http, baseURL: jamfProURL, auth: auth)
            let ea = JamfEAHandler(logger: logger, http: http, baseURL: jamfProURL, auth: auth)
            var canUpdateEAValues = false

            if let cachedComputerID = computerID {
                logger.develop("Using cached Jamf Computer ID: \(cachedComputerID)")
                canUpdateEAValues = true
            } else if let cid = await api.getComputerIDBySerialV3(serial: serial) {
                try guardNotShuttingDown(logger: logger, phase: "computer id lookup")
                computerID = cid
                state.computerID = cid
                canUpdateEAValues = true
            } else {
                logger.info("ComputerID not available; EA update skipped for this run.")
            }

            if effectiveAPIUpdate {
                var needed = ["Notary Runner", "Notary Issues", "Notary Compliance"]
                needed.append("Notary Percent")

                let resolved = await ea.resolveEADefinitionIDs(
                    names: needed,
                    cache: state.eaDefinitionIDs,
                    cacheUpdatedAt: state.eaCacheUpdatedAt,
                    refreshAttemptedAt: state.eaCacheRefreshAttemptedAt,
                    refreshFailCount: state.eaCacheRefreshFailCount,
                    staleAfter: 24 * 60 * 60,
                    cooldown: 60 * 60
                )

                idsByName = resolved.ids

                try guardNotShuttingDown(logger: logger, phase: "ea definition resolution")

                if resolved.didAttempt || resolved.didUpdate {
                    state.eaCacheRefreshAttemptedAt = resolved.newAttemptedAt
                    state.eaCacheRefreshFailCount = resolved.newFailCount
                    if resolved.didUpdate {
                        state.eaDefinitionIDs = resolved.newCache
                        state.eaCacheUpdatedAt = resolved.newCacheUpdatedAt
                    }
                }

                if !effectiveReportPercent, idsByName["Notary Percent"] != nil {
                    // Percent reporting is opt-in by presence of the EA. This
                    // lets older deployments keep working without another knob.
                    effectiveReportPercent = true
                    state.reportpercent = true
                    logger.info("EA found: Notary Percent; enabling compliance percent reporting.")

                    if state.lastReportedCompliancePercentValue != proof.compliancePercentValue {
                        shouldTransport = true
                        transportReason = .percentChanged
                    }
                }

                logger.info(transportReason.logMessage)

                if !shouldTransport {
                    effectiveAPIUpdate = false
                }

                if effectiveAPIUpdate, canUpdateEAValues, let cid = computerID {
                    if let id = idsByName["Notary Runner"] {
                        _ = await ea.updateEA(
                            computerID: cid,
                            definitionID: id,
                            value: proof.statusValue(versionLabel: NotaryVersion.label)
                        )
                    } else {
                        logger.warn("EA not found: Notary Runner")
                    }

                    if let id = idsByName["Notary Issues"] {
                        _ = await ea.updateEA(
                            computerID: cid,
                            definitionID: id,
                            value: proof.issuesValue
                        )
                    } else {
                        logger.warn("EA not found: Notary Issues")
                    }

                    if let id = idsByName["Notary Compliance"] {
                        _ = await ea.updateEA(
                            computerID: cid,
                            definitionID: id,
                            value: proof.complianceValue
                        )
                    } else {
                        logger.warn("EA not found: Notary Compliance")
                    }

                    if effectiveReportPercent {
                        if let id = idsByName["Notary Percent"] {
                            _ = await ea.updateEA(
                                computerID: cid,
                                definitionID: id,
                                value: proof.compliancePercentValue
                            )
                        } else {
                            logger.warn("EA not found: Notary Percent")
                        }
                    }
                } else if !shouldTransport {
                    logger.info("EA update disabled for this run (no transport changes and heartbeat not due).")
                } else if !canUpdateEAValues {
                    logger.info("EA update disabled for this run (ComputerID not available).")
                }
            } else {
                logger.info(transportReason.logMessage)
                logger.info("EA update disabled for this run (Jamf unavailable or missing prerequisites).")
            }

            let persistedTokenState = await auth.persistedTokenState()
            // Store only the token and its expiry, not another credential copy.
            // Reusing a valid token across cycles protects Jamf Pro during DB
            // timeout storms by avoiding needless OAuth token creation.
            state.jamfBearerToken = persistedTokenState.token
            state.jamfBearerExpirationEpoch = persistedTokenState.expirationEpoch
        } else {
            logger.info(transportReason.logMessage)
            logger.info("EA update disabled (configured off or missing prerequisites).")
        }

        try guardNotShuttingDown(logger: logger, phase: "local transport write")

        var didWriteTransportToPlist = false
        if shouldTransport {
            do {
                let recon = ReconEAStore(path: "/var/db/notary.plist")
                var reconValues = [
                    "Notary Runner": proof.statusValue(versionLabel: NotaryVersion.label),
                    "Notary Issues": proof.issuesValue,
                    "Notary Compliance": proof.complianceValue
                ]
                if effectiveReportPercent {
                    reconValues["Notary Percent"] = proof.compliancePercentValue
                }
                try recon.write(values: reconValues)
                didWriteTransportToPlist = true
                logger.develop("Recon EA values written to notary.plist")
            } catch {
                logger.warn("Failed to write recon EA values to notary.plist: \(error)")
            }
        } else {
            logger.develop("Recon EA values left unchanged; next heartbeat not yet due.")
        }

        state.lastRunAt = Date()
        state.lastRunOK = true
        for run in execution.rawRuns {
            let key = run.spec.persistenceKey
            switch run.result.status {
            case .pass:
                state.lastKnownPassingChecks[key] = LastKnownPassingCheck(
                    details: run.result.details,
                    recordedAt: proof.generatedAt
                )
            case .fail, .unknown:
                state.lastKnownPassingChecks.removeValue(forKey: key)
            case .skipped, .notConfigured, .cancelled, .timedOut:
                // These outcomes do not prove a benchmark has newly passed or
                // failed; preserve the prior fallback state for the next report.
                break
            }
        }

        if didWriteTransportToPlist {
            Transporter.applySuccessfulTransport(
                proof: proof,
                state: &state,
                at: proof.generatedAt,
                reportPercent: effectiveReportPercent
            )
        }

        UptimeAlertCoordinator.handleIfNeeded(
            execution: execution,
            state: &state,
            logger: logger
        )

        try guardNotShuttingDown(logger: logger, phase: "state persistence")
        try store.save(state)

        try guardNotShuttingDown(logger: logger, phase: "public report persistence")

        do {
            let publicReport = NotaryPublicReport(
                generatedAt: proof.generatedAt,
                lastRunAt: state.lastRunAt,
                lastTransportUpdateAt: state.lastTransportUpdateAt,
                runnerStatus: proof.statusValue(versionLabel: NotaryVersion.label),
                issuesValue: proof.issuesValue,
                complianceValue: proof.complianceValue,
                passedCount: proof.passedCount,
                failedCount: proof.failedCount,
                unknownCount: proof.unknownCount,
                timedOutCount: proof.timedOutCount,
                skippedCount: proof.skippedCount,
                compliancePercent: proof.compliancePercent,
                marketingVersion: NotaryVersion.marketingVersion,
                versionLabel: NotaryVersion.label,
                serialNumber: serial,
                hardwareModel: hardwareModel,
                managementHost: jamfProURL?.host,
                managementComputerID: state.computerID
            )
            try NotaryPublicReportStore().save(publicReport)
        } catch {
            logger.warn("Failed to write public Notary report: \(error)")
        }

        logger.info("Notary \(NotaryVersion.label) finished.")
    }

    private static func guardNotShuttingDown(logger: HardenLogger, phase: String) throws {
        if ShutdownCoordinator.shared.isShutdownRequested {
            let reason = ShutdownCoordinator.shared.reason
            logger.warn("[SHUTDOWN] Aborting \(phase) due to \(reason)")
            throw ShutdownError.requested(reason: reason)
        }
    }

    private static func deferForTransientManagedConfigGapIfNeeded(
        configurationSnapshot: ManagedConfigurationSnapshot,
        state: inout RunnerState,
        store: SecurePlistStore<RunnerState>,
        logger: HardenLogger,
        now: Date = Date()
    ) throws -> Bool {
        if configurationSnapshot.hasManagedContent {
            state.lastManagedConfigSeenAt = now
            state.managedConfigMissingSince = nil
            return false
        }

        guard state.lastManagedConfigSeenAt != nil else {
            return false
        }

        if state.managedConfigMissingSince == nil {
            state.managedConfigMissingSince = now
        }

        guard let missingSince = state.managedConfigMissingSince else {
            return false
        }

        let missingFor = now.timeIntervalSince(missingSince)
        if missingFor < managedConfigGraceInterval {
            let remainingSeconds = Int((managedConfigGraceInterval - missingFor).rounded(.up))
            logger.warn("[ManagedConfig] Managed profile values disappeared temporarily; deferring this cycle for up to 5 minutes while the profile reloads (\(remainingSeconds)s remaining).")
            try guardNotShuttingDown(logger: logger, phase: "managed config grace persistence")
            try store.save(state)
            logger.info("Notary \(NotaryVersion.label) deferred: managed configuration temporarily unavailable.")
            return true
        }

        logger.warn("[ManagedConfig] Managed profile values are still unavailable after 5 minutes; continuing with the current empty snapshot.")
        return false
    }
}
