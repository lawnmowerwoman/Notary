import Foundation

enum ReconEAStoreError: Error {
    case readFailed(Error)
    case decodeFailed
    case encodeFailed(Error)
    case writeFailed(Error)
    case lockFailed(Error)
}

package final class ReconEAStore {

    private let url: URL

    package init(path: String = "/var/db/notary.plist") {
        self.url = URL(fileURLWithPath: path)
    }

    package func write(values: [String: String]) throws {
        let lock = FileLock(targetURL: url)
        do { try lock.lock() } catch { throw ReconEAStoreError.lockFailed(error) }
        defer { lock.unlock() }

        var dict: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                if !data.isEmpty {
                    var format = PropertyListSerialization.PropertyListFormat.xml
                    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
                    dict = (obj as? [String: Any]) ?? [:]
                }
            } catch {
                throw ReconEAStoreError.readFailed(error)
            }
        }

        // Merge/overwrite only these EA keys
        for (k, v) in values {
            dict[k] = v
        }

        do {
            let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try atomicWrite(data: out, to: url)
        } catch let e as ReconEAStoreError {
            throw e
        } catch {
            throw ReconEAStoreError.encodeFailed(error)
        }
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp.\(UUID().uuidString)")

        do {
            try data.write(to: tmp, options: [.completeFileProtectionUnlessOpen])
            _ = try fm.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])
        } catch {
            try? fm.removeItem(at: tmp)
            throw ReconEAStoreError.writeFailed(error)
        }
    }

    // Minimal flock lock (same pattern as your SecurePlistStore)
    private final class FileLock {
        private let lockURL: URL
        private var fd: Int32 = -1

        init(targetURL: URL) {
            self.lockURL = targetURL.appendingPathExtension("lock")
        }

        func lock() throws {
            let path = lockURL.path
            fd = open(path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if flock(fd, LOCK_EX) != 0 {
                let err = errno
                close(fd); fd = -1
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
            }
        }

        func unlock() {
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }

        deinit { unlock() }
    }
}
