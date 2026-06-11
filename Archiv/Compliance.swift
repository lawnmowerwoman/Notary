import Foundation

struct IssueRecord: Codable {
  let id: String
  let message: String
  let severity: Severity
}

final class ComplianceContext {
  private(set) var tests: Int = 0
  private(set) var majorIssues: Int = 0
  private(set) var issues: [IssueRecord] = []

  private let logger: HardenLogger

  init(logger: HardenLogger) {
    self.logger = logger
  }

  /// Equivalent to _pass_ok "ID" "message"
  func passOK(_ id: String, _ message: String) {
    tests += 1
    logger.debug("[ OK ]   \(id): \(message)")
  }

  /// Equivalent to _mark_issue "ID" "message" severity
    func markIssue(_ id: String, _ message: String, severity: Severity) {
        tests += 1
        issues.append(IssueRecord(id: id, message: message, severity: severity))

        switch severity {
            case .high:
                majorIssues += 1
                logger.issue("[FAILED] \(id): \(message)")

            case .medium:
                logger.issue("[ISSUE]  \(id): \(message)")

            case .low:
                logger.info("[MINOR]  \(id): \(message)")
        }

  }

  /// Helper: derive severity from pentabool mode.
  /// abs(mode) == 2 => high else low
    func severity(from mode: PentaMode) -> Severity {
        switch abs(mode.rawValue) {
            case 2:
                return .high
            case 1:
                return .low
            default:
                return .low
        }
    }

}
