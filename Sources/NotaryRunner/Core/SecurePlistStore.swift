import Foundation
import Darwin

/// Minimal logging interface for SecurePlistStore.
/// If your existing Logger type has `warn(_:)`, just add:
/// `extension Logger: PlistStoreLogger {}` (see below).
package protocol PlistStoreLogger {
    func warn(_ message: String)
}

/// A small, opinionated secure plist store for HardeningRunner:
/// - Preferred path: /var/db/notary.plist (root only)
/// - Fallback path: /tmp/notary.<uid>.plist (non-root)
/// - Binary plist, permissions 0600, atomic write
/// - Advisory locking via flock
package final class SecurePlistStore<Value: Codable> {

    enum StoreError: Error, CustomStringConvertible {
        case encodeFailed(Error)
        case decodeFailed(Error)
        case writeFailed(Error)
        case readFailed(Error)
        case invalidDirectory(URL)
        case cannotEnsureDirectory(URL, Error)
        case cannotApplyAttributes(URL, Error)
        case lockFailed(URL, Error)

        var description: String {
            switch self {
            case .encodeFailed(let e): return "Encode failed: \(e)"
            case .decodeFailed(let e): return "Decode failed: \(e)"
            case .writeFailed(let e): return "Write failed: \(e)"
            case .readFailed(let e): return "Read failed: \(e)"
            case .invalidDirectory(let url): return "Invalid directory: \(url.path)"
            case .cannotEnsureDirectory(let url, let e): return "Cannot ensure directory \(url.path): \(e)"
            case .cannotApplyAttributes(let url, let e): return "Cannot apply file attributes \(url.path): \(e)"
            case .lockFailed(let url, let e): return "Lock failed for \(url.path): \(e)"
            }
        }
    }

    // MARK: - Config

    private let logger: PlistStoreLogger?

    package init(logger: PlistStoreLogger? = nil) {
        self.logger = logger
    }

    /// Preferred (root-only) location.
    private let rootURL = URL(fileURLWithPath: "/var/db/notary.plist", isDirectory: false)

    /// Fallback for non-root (per-UID to avoid collisions/symlink games).
    private var tmpURL: URL {
        let uid = Int(geteuid())
        return URL(fileURLWithPath: "/tmp/notary.\(uid).plist", isDirectory: false)
    }

    private var isRoot: Bool { geteuid() == 0 }

    private var didWarnAboutFallback = false

    package var effectiveURL: URL {
        if isRoot { return rootURL }
        if !didWarnAboutFallback {
            logger?.warn("Not running as root; using fallback plist path: \(tmpURL.path)")
            didWarnAboutFallback = true
        }
        return tmpURL
    }


    // MARK: - Codable <-> plist

    private let encoder: PropertyListEncoder = {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return e
    }()

    private let decoder = PropertyListDecoder()

    // MARK: - Public API

    package func load() throws -> Value? {
        let url = effectiveURL
        let lock = FileLock(targetURL: url)
        do {
            try lock.lock(timeoutSeconds: 5)
        } catch {
            // Noch ein kleines Goodie (optional, aber ich mag’s)
            // Wenn du im StoreError.lockFailed den Fehlercode ETIMEDOUT siehst, kannst du in details
            // schön „lock timeout“ schreiben. Das hilft später beim Debuggen enorm.
            throw StoreError.lockFailed(url, error)
        }
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw StoreError.decodeFailed(error)
        }
    }

    package func save(_ value: Value) throws {
        let url = effectiveURL
        let directory = url.deletingLastPathComponent()
        try ensureDirectoryExists(directory)

        let lock = FileLock(targetURL: url)
        do {
            try lock.lock(timeoutSeconds: 5)
        } catch {
            throw StoreError.lockFailed(url, error)
        }
        defer { lock.unlock() }

        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw StoreError.encodeFailed(error)
        }

        do {
            try atomicWrite(data: data, to: url)
            try applySecureAttributes(to: url)
        } catch let e as StoreError {
            throw e
        } catch {
            throw StoreError.writeFailed(error)
        }
    }

    package func delete() throws {
        let url = effectiveURL
        let lock = FileLock(targetURL: url)
        do {
            try lock.lock(timeoutSeconds: 5)
        } catch {
            throw StoreError.lockFailed(url, error)
        }
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Optional helper: if the file exists but permissions/owner are wrong, try to fix them.
    package func enforceSecurityIfPresent() throws {
        let url = effectiveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try applySecureAttributes(to: url)
    }

    // MARK: - Internals

    private func ensureDirectoryExists(_ dir: URL) throws {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
            guard isDir.boolValue else { throw StoreError.invalidDirectory(dir) }
            return
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw StoreError.cannotEnsureDirectory(dir, error)
        }
    }

    /// Atomic write using a temp file in the same directory + replaceItemAt.
    private func atomicWrite(data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()

        // Unique temp file alongside the target (important for atomic replace semantics).
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp.\(UUID().uuidString)")

        do {
            // Write temp file. (If file protection is unsupported in your context, remove the option.)
            try data.write(to: tmp, options: [.completeFileProtectionUnlessOpen])

            // Replace target atomically (creates if missing)
            _ = try fm.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])
        } catch {
            try? fm.removeItem(at: tmp)
            throw StoreError.writeFailed(error)
        }
    }

    /// Applies mode 0600 and (when root) owner/group 0:0.
    private func applySecureAttributes(to url: URL) throws {
        let fm = FileManager.default

        let perms: NSNumber = 0o600
        var attrs: [FileAttributeKey: Any] = [
            .posixPermissions: perms
        ]

        if isRoot {
            attrs[.ownerAccountID] = NSNumber(value: 0)
            attrs[.groupOwnerAccountID] = NSNumber(value: 0)
        }

        do {
            try fm.setAttributes(attrs, ofItemAtPath: url.path)
        } catch {
            throw StoreError.cannotApplyAttributes(url, error)
        }
    }

    // MARK: - Lock helper (flock)

    enum FileLockError: Error {
        case timeout(URL)
        case underlying(Error)
    }

    private final class FileLock {
        private let lockURL: URL
        private var fd: Int32 = -1

        init(targetURL: URL) {
            self.lockURL = targetURL.appendingPathExtension("lock")
        }

        /// Blocking lock (legacy behavior)
        func lock() throws {
            try lock(timeoutSeconds: nil)
        }

        /// Lock with optional timeout. If timeoutSeconds is nil, blocks indefinitely.
        func lock(timeoutSeconds: TimeInterval?) throws {
            let path = lockURL.path

            fd = open(path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }

            guard let timeoutSeconds else {
                if flock(fd, LOCK_EX) != 0 {
                    let err = errno
                    close(fd); fd = -1
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
                }
                return
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)

            while true {
                if try tryLockOnce() {
                    return
                }

                if Date() >= deadline {
                    close(fd); fd = -1
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
                }

                usleep(50_000)
            }
        }

        private func tryLockOnce() throws -> Bool {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return true
            }

            if errno == EWOULDBLOCK {
                return false
            }

            let err = errno
            close(fd); fd = -1
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
        }

        func unlock() {
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }

        deinit {
            unlock()
        }
    }
}

// If your logger type is literally named `Logger` and it already has `warn(_:)`,
// uncomment this extension:
//
//extension Logger: PlistStoreLogger {}
