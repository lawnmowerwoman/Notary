import Foundation

package enum ShutdownError: Error {
    case requested(reason: String)
}

package final class ShutdownCoordinator: @unchecked Sendable {
    package static let shared = ShutdownCoordinator()

    private let lock = NSLock()
    private var shutdownRequested = false
    private var shutdownReason = "shutdown requested"

    private init() {}

    package func requestShutdown(reason: String) {
        lock.lock()
        shutdownRequested = true
        shutdownReason = reason
        lock.unlock()
    }

    package func reset() {
        lock.lock()
        shutdownRequested = false
        shutdownReason = "shutdown requested"
        lock.unlock()
    }

    package var isShutdownRequested: Bool {
        lock.lock()
        let value = shutdownRequested
        lock.unlock()
        return value
    }

    package var reason: String {
        lock.lock()
        let value = shutdownReason
        lock.unlock()
        return value
    }
}
