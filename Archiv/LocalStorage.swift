import Foundation

// What you persist across runs (expand as needed)
struct RunnerState: Codable {
  var jamfClientID: String?
  var jamfClientSecret: String?

  var lastRunAt: Date?
  var lastComputerID: Int?
  var lastSerial: String?

  var lastExitCode: Int?
  var lastIssues: [String]?   // e.g. ["XPR-1 ...", "FV-1 ..."]
}

final class SecurePlistStore {

  private let logger: HardenLogger
  private let url: URL
  private let isRoot: Bool

  init(logger: HardenLogger, path: String = "/var/db/awxcr.plist") {
    self.logger = logger
    self.isRoot = (geteuid() == 0)

    let effectivePath = isRoot ? path : "/tmp/awxcr.plist"
    self.url = URL(fileURLWithPath: effectivePath)

    ensureDirectory()
    touchIfMissing()
    fixPermissionsIfRoot()
  }

  func load() -> RunnerState {
    do {
      let data = try Data(contentsOf: url)
      if data.isEmpty {
        return RunnerState()
      }
      let dec = PropertyListDecoder()
      return try dec.decode(RunnerState.self, from: data)
    } catch {
      logger.warn("Storage load failed (\(url.path)): \(error). Using empty state.")
      return RunnerState()
    }
  }

  func save(_ state: RunnerState) {
    do {
      let enc = PropertyListEncoder()
      enc.outputFormat = .binary
      let data = try enc.encode(state)

      // Atomic write: write to temp then replace
      let tmp = URL(fileURLWithPath: url.path + ".tmp")
      try data.write(to: tmp, options: .atomic)

      // Replace
      _ = try? FileManager.default.removeItem(at: url)
      try FileManager.default.moveItem(at: tmp, to: url)

      fixPermissionsIfRoot()
    } catch {
      logger.error("Storage save failed (\(url.path)): \(error)")
    }
  }

  // MARK: - Helpers

  private func ensureDirectory() {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  private func touchIfMissing() {
    if !FileManager.default.fileExists(atPath: url.path) {
      _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }
  }

  private func fixPermissionsIfRoot() {
    guard isRoot else { return }
    chmod(url.path, 0o600)   // root-only read/write
    chown(url.path, 0, 0)    // root:wheel (0:0)
  }

  // Convenience: quick setters so you don’t juggle full state everywhere
  func update(_ mutate: (inout RunnerState) -> Void) {
    var s = load()
    mutate(&s)
    save(s)
  }
}
