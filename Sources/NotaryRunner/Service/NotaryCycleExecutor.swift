import Foundation
import NotaryCore
import NotaryTransportImplementation

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

        let store = SecurePlistStore<RunnerState>(logger: logger, preservedExternalKeys: ["apptoken"])
        var state = try store.load() ?? RunnerState()

        let configuredAPIUpdate = state.apiupdate ?? true
        let configuredReportPercent = state.reportpercent ?? false
        let effectiveReportPercent = configuredReportPercent
        var effectiveRemoteTransport = configuredAPIUpdate

        let clientID = state.jamfClientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientSecret = state.jamfClientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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

        let appTokenAuthorization = NotaryAppTokenHandler.evaluate()
        NotaryAppTokenHandler.log(appTokenAuthorization, logger: logger)
        if effectiveRemoteTransport, !appTokenAuthorization.allowsTransporter {
            logger.warn("Remote transport disabled because the App Token does not grant the transporter capability.")
            effectiveRemoteTransport = false
        }

        let telemetry = TelemetrySampler().sample(
            options: TelemetrySamplingOptions(
                wirelessReporting: configurationSnapshot.config.telemetry.wirelessReporting
            )
        )
        let connectionValue = telemetry.wireless?.connectionValue

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

        if !effectiveReportPercent, state.lastReportedCompliancePercentValue != nil {
            state.reportpercent = false
        }

        let transportDecision = Transporter.decide(
            proof: proof,
            state: state,
            at: proof.generatedAt,
            heartbeatInterval: transporterHeartbeatInterval,
            reportPercent: effectiveReportPercent,
            connectionValue: connectionValue
        )
        let transportReason = transportDecision.reason

        let jamfProURL = JamfLocalConfig.jamfProURL()
        if let jamfProURL {
            logger.info("Management URL detected: \(jamfProURL.absoluteString)")
        } else {
            logger.info("Management URL unavailable right now; remote transport skipped for this run.")
            effectiveRemoteTransport = false
        }

        if effectiveRemoteTransport, NotaryTransport.availability == .confidential, (clientID.isEmpty || clientSecret.isEmpty) {
            logger.info("Transport credentials missing; remote transport skipped for this run.")
            effectiveRemoteTransport = false
        }

        try guardNotShuttingDown(logger: logger, phase: "pre-transport")

        logger.info(transportReason.logMessage)

        if effectiveRemoteTransport {
            let service = NotaryTransport.makeService()
            let request = TransportRequest(
                shouldTransport: transportDecision.shouldUpdate,
                serialNumber: serial,
                baseURL: jamfProURL,
                credentials: TransportCredentials(clientID: clientID, clientSecret: clientSecret),
                cachedComputerID: state.computerID,
                bearerToken: state.jamfBearerToken,
                bearerExpirationEpoch: state.jamfBearerExpirationEpoch,
                eaState: TransportEAState(
                    definitionIDs: state.eaDefinitionIDs,
                    cacheUpdatedAt: state.eaCacheUpdatedAt,
                    refreshAttemptedAt: state.eaCacheRefreshAttemptedAt,
                    refreshFailCount: state.eaCacheRefreshFailCount
                ),
                proofValues: TransportProofValues(
                    runner: proof.statusValue(versionLabel: NotaryVersion.label),
                    issues: proof.issuesValue,
                    compliance: proof.complianceValue,
                    percent: effectiveReportPercent ? proof.compliancePercentValue : nil,
                    connection: connectionValue
                )
            )

            let result = await service.perform(request)
            for message in result.logMessages {
                switch result.status {
                case .completed, .skipped:
                    logger.info(message)
                case .implementationUnavailable:
                    logger.warn(message)
                case .failed:
                    logger.error(message)
                }
            }

            if let computerID = result.computerID {
                state.computerID = computerID
            }
            state.jamfBearerToken = result.bearerToken
            state.jamfBearerExpirationEpoch = result.bearerExpirationEpoch
            if let eaState = result.eaState {
                state.eaDefinitionIDs = eaState.definitionIDs
                state.eaCacheUpdatedAt = eaState.cacheUpdatedAt
                state.eaCacheRefreshAttemptedAt = eaState.refreshAttemptedAt
                state.eaCacheRefreshFailCount = eaState.refreshFailCount
            }
        } else if configuredAPIUpdate {
            logger.info("Remote transport disabled for this run.")
        }

        try guardNotShuttingDown(logger: logger, phase: "local transport write")

        var didWriteTransportToPlist = false
        if transportDecision.shouldUpdate {
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
                if let connectionValue {
                    reconValues["Notary Connection"] = connectionValue
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
                reportPercent: effectiveReportPercent,
                connectionValue: connectionValue
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
