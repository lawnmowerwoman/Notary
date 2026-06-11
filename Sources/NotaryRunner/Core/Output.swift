import Foundation

enum Output {
    static func write(report: Report, asJSON: Bool) throws {
        if asJSON {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        } else {
            // human readable
            print("Facts:")
            for f in report.facts { print("  - \(f.key): \(f.value)") }
            print("Issues:")
            if report.issues.isEmpty {
                print("  (none)")
            } else {
                for i in report.issues { print("  - [\(i.severity.rawValue)] \(i.id): \(i.message)") }
            }
        }
    }
}
