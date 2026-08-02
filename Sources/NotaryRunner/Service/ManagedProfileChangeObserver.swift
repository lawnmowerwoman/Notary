import Foundation
import CoreFoundation
import NotaryCore

/// Watches Darwin notifications emitted by the managed-preferences stack and
/// triggers a debounced reload callback. This is intended for the future
/// Engagement service and keeps the one-shot Runner mode untouched.
final class ManagedProfileChangeObserver {

    private static let notifications: [String] = [
        "com.apple.ManagedClient.preferencesDidChange",
        "com.apple.MCX.ManagedPreferencesChanged",
    ]

    private let logger: HardenLogger
    private let reloadDelay: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "de.twocent.notary.profile-change")

    private var isObserving = false
    private var pendingWorkItem: DispatchWorkItem?

    init(
        logger: HardenLogger,
        reloadDelay: TimeInterval = 0.5,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.logger = logger
        self.reloadDelay = reloadDelay
        self.onChange = onChange
    }

    func startObserving() {
        guard !isObserving else { return }
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        for name in Self.notifications {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let me = Unmanaged<ManagedProfileChangeObserver>
                        .fromOpaque(observer)
                        .takeUnretainedValue()
                    me.handleNotification()
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        isObserving = true
        logger.warn("[ManagedProfileChangeObserver] Listening for managed profile changes")
    }

    func stopObserving() {
        guard isObserving else { return }
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        for name in Self.notifications {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                CFNotificationName(rawValue: name as CFString),
                nil
            )
        }

        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        isObserving = false
        logger.warn("[ManagedProfileChangeObserver] Stopped listening for managed profile changes")
    }

    deinit {
        stopObserving()
    }

    private func handleNotification() {
        logger.warn("[ManagedProfileChangeObserver] MDM notification received – scheduling config reload")

        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [onChange] in
            onChange()
        }
        pendingWorkItem = workItem

        queue.asyncAfter(deadline: .now() + reloadDelay, execute: workItem)
    }
}
