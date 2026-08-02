import Foundation

struct Fact: Codable {
  let key: String
  let value: String
}

struct Issue: Codable {
  let id: String
  let severity: Severity
  let message: String
}

struct Report: Codable {
  let facts: [Fact]
  let issues: [Issue]
}

struct AuditResult {
  var facts: [Fact] = []
  var issues: [Issue] = []
}

protocol Audit {
  func check(process: ProcessRunner, logger: HardenLogger) -> AuditResult
  func remediate(process: ProcessRunner, logger: HardenLogger) -> AuditResult
}
