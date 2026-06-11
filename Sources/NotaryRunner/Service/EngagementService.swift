import Foundation
import CoreFoundation
import Darwin
import NotaryCore

final class EngagementService: @unchecked Sendable {
    private let logger: HardenLogger
    private let domain: String
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "de.twocent.notary.engagement")

    private var timer: DispatchSourceTimer?
    private var profileObserver: ManagedProfileChangeObserver?
    private var runLoop: CFRunLoop?

    private var isRunning = false
    private var isStopping = false
    private var isExecuting = false
    private var rerunPending = false
    private var restartScheduled = false
    private let caps: RunnerCapabilities

    init(logger: HardenLogger, domain: String, interval: TimeInterval) {
        self.logger = logger
        self.domain = domain
        self.interval = interval
        self.caps = RunnerCapabilities.detect(logger: logger)
    }

    func runForever() {
        guard !isRunning else {
            logger.warn("[EngagementService] runForever() called while already running")
            return
        }

        isRunning = true
        isStopping = false
        ShutdownCoordinator.shared.reset()
        runLoop = CFRunLoopGetCurrent()

        logger.start("Notary Engagement started ✨ \(NotaryVersion.label) (v\(NotaryVersion.marketingVersion), interval=\(Int(interval))s)")
        enqueueRun(reason: "startup reconciliation")
        startPeriodicTimer()
        startProfileObserver()
        logger.warn("[EngagementService] Run loop started – waiting for timer and profile changes")
        CFRunLoopRun()
        stop()
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            guard !self.isStopping else { return }

            self.isStopping = true
            self.timer?.setEventHandler {}
            self.timer?.cancel()
            self.timer = nil

            self.profileObserver?.stopObserving()
            self.profileObserver = nil

            self.rerunPending = false

            if let runLoop = self.runLoop {
                CFRunLoopStop(runLoop)
            }

            self.isRunning = false
            self.logger.warn("[EngagementService] Stopped")
        }
    }

    func requestReload(reason: String = "signal reload") {
        enqueueRun(reason: reason)
    }

    private func startPeriodicTimer() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.enqueueRun(reason: "periodic interval")
        }
        self.timer = timer
        timer.resume()
        logger.warn("[EngagementService] Periodic timer armed for \(Int(interval)) seconds")
    }

    private func startProfileObserver() {
        guard profileObserver == nil else { return }

        let observer = ManagedProfileChangeObserver(logger: logger) { [weak self] in
            self?.enqueueRun(reason: "managed profile change")
        }
        self.profileObserver = observer
        observer.startObserving()
    }

    private func enqueueRun(reason: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning, !self.isStopping else { return }

            if self.isExecuting {
                if !self.rerunPending {
                    self.rerunPending = true
                    self.logger.info("[EngagementService] Run requested while busy – queued rerun (\(reason))")
                }
                return
            }

            self.isExecuting = true
            Task { [weak self] in
                await self?.performRun(reason: reason)
            }
        }
    }

    private func performRun(reason: String) async {
        guard !ShutdownCoordinator.shared.isShutdownRequested else {
            logger.warn("[EngagementService] Cycle skipped due to shutdown request")
            queue.async { [weak self] in
                self?.isExecuting = false
            }
            return
        }

        logger.info("[EngagementService] Cycle started (\(reason))")
        do {
            try await NotaryCycleExecutor.execute(domain: domain, logger: logger, caps: caps, engagementMode: true)
        } catch let error as CheckExecutionError {
            switch error {
            case .timeoutCascade(let consecutive, let total):
                logger.error("[EngagementService] Timeout cascade detected (\(consecutive) consecutive / \(total) total outer timeouts); scheduling full service restart.")
                scheduleProcessRestart(reason: "timeout cascade")
            }
        } catch let error as ShutdownError {
            logger.warn("[EngagementService] Cycle aborted (\(reason)): \(error)")
        } catch {
            logger.error("[EngagementService] Cycle failed (\(reason)): \(error)")
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.isExecuting = false
            guard !self.isStopping else { return }
            if self.rerunPending {
                self.rerunPending = false
                self.enqueueRun(reason: "queued rerun")
            }
        }
    }

    private func scheduleProcessRestart(reason: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.restartScheduled else { return }

            self.restartScheduled = true
            self.isStopping = true
            self.rerunPending = false

            self.timer?.setEventHandler {}
            self.timer?.cancel()
            self.timer = nil

            self.profileObserver?.stopObserving()
            self.profileObserver = nil

            self.logger.error("[EngagementService] Restarting process via launchd recovery (\(reason)).")

            if let runLoop = self.runLoop {
                CFRunLoopStop(runLoop)
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                Darwin.exit(75)
            }
        }
    }

    deinit {
        stop()
    }
}
