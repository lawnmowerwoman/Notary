import Foundation
import NotaryCore

final class ProcessSignalObserver: @unchecked Sendable {
    private let logger: HardenLogger
    private let queue = DispatchQueue(label: "de.twocent.notary.signals")
    private let onTerminate: @Sendable (Int32) -> Void
    private let onReload: @Sendable () -> Void

    private var signalSources: [DispatchSourceSignal] = []
    private var isObserving = false

    init(
        logger: HardenLogger,
        onTerminate: @escaping @Sendable (Int32) -> Void,
        onReload: @escaping @Sendable () -> Void
    ) {
        self.logger = logger
        self.onTerminate = onTerminate
        self.onReload = onReload
    }

    func startObserving() {
        guard !isObserving else { return }

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)

        signalSources = [
            makeSignalSource(SIGTERM) { [weak self] in
                ShutdownCoordinator.shared.requestShutdown(reason: "SIGTERM")
                self?.logger.warn("[ProcessSignalObserver] Received SIGTERM - stopping engagement")
                self?.onTerminate(SIGTERM)
            },
            makeSignalSource(SIGINT) { [weak self] in
                ShutdownCoordinator.shared.requestShutdown(reason: "SIGINT")
                self?.logger.warn("[ProcessSignalObserver] Received SIGINT - stopping engagement")
                self?.onTerminate(SIGINT)
            },
            makeSignalSource(SIGHUP) { [weak self] in
                self?.logger.warn("[ProcessSignalObserver] Received SIGHUP - triggering immediate reload")
                self?.onReload()
            }
        ]

        signalSources.forEach { $0.resume() }
        isObserving = true
        logger.warn("[ProcessSignalObserver] Installed handlers for SIGTERM, SIGINT and SIGHUP")
    }

    func stopObserving() {
        guard isObserving else { return }
        signalSources.forEach { source in
            source.setEventHandler {}
            source.cancel()
        }
        signalSources.removeAll()
        isObserving = false
        logger.warn("[ProcessSignalObserver] Signal handlers removed")
    }

    deinit {
        stopObserving()
    }

    private func makeSignalSource(_ signalNumber: Int32, handler: @escaping @Sendable () -> Void) -> DispatchSourceSignal {
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
        source.setEventHandler(handler: handler)
        return source
    }
}
