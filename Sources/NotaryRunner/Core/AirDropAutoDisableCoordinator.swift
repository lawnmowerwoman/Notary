import Foundation

package enum AirDropAutoDisableCoordinator {
    package static func handleIfNeeded(
        config: ManagedConfig,
        state: inout RunnerState,
        logger: HardenLogger,
        now: Date = Date()
    ) {
        let timeoutMinutes = config.perUser.airDropAutoDisableMinutes
        guard timeoutMinutes > 0 else {
            if !state.airDropEnabledSinceByUser.isEmpty {
                state.airDropEnabledSinceByUser.removeAll()
                logger.info("[AirDropAutoDisable] Disabled by config; cleared tracked AirDrop timers.")
            }
            return
        }

        let users = PerUserPreferences.localUsers()
        let currentUsers = Set(users)
        for trackedUser in Array(state.airDropEnabledSinceByUser.keys) where !currentUsers.contains(trackedUser) {
            state.airDropEnabledSinceByUser.removeValue(forKey: trackedUser)
        }

        let timeoutSeconds = TimeInterval(timeoutMinutes * 60)
        for user in users {
            guard let isEnabled = isAirDropExplicitlyEnabled(user: user, logger: logger) else {
                state.airDropEnabledSinceByUser.removeValue(forKey: user)
                continue
            }

            guard isEnabled else {
                state.airDropEnabledSinceByUser.removeValue(forKey: user)
                continue
            }

            let firstSeen = state.airDropEnabledSinceByUser[user] ?? now
            state.airDropEnabledSinceByUser[user] = firstSeen

            guard now.timeIntervalSince(firstSeen) >= timeoutSeconds else {
                let remaining = Int((timeoutSeconds - now.timeIntervalSince(firstSeen)).rounded(.up))
                logger.develop("[AirDropAutoDisable] AirDrop enabled for user \(user); \(remaining)s remaining before auto-disable.")
                continue
            }

            enforceAirDropDisabled(user: user, logger: logger)
            state.airDropEnabledSinceByUser.removeValue(forKey: user)
            logger.info("[AirDropAutoDisable] AirDrop disabled for user \(user) after \(timeoutMinutes) minutes.")
        }
    }
}
