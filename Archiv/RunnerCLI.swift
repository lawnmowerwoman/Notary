import Foundation
import ArgumentParser

@main
struct HardeningRunner: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "hardening-runner",
    abstract: "Compliance check + remediation runner for macOS hardening."
  )

  @Flag(help: "Dump raw effective managed config and exit.")
  var dumpConfig: Bool = false

  @Flag(help: "Dump config with Pentabool-resolved values and exit.")
  var dumpResolved: Bool = false

  @Option(help: "Preferences domain to read (default: de.apfelwerk.harden).")
  var domain: String = "de.apfelwerk.harden"


  func run() throws {
    let log = Log(sinkPath: nil)

    if dumpConfig || dumpResolved {
        let topKeys = GeneratedKeys.topKeys
        let modeKeys = GeneratedKeys.modeKeys
        let parameterKeys = GeneratedKeys.parameterKeys

      let rawSnapshot = ManagedPrefs.snapshot(domain: domain, topLevelKeys: topKeys)

      var output: [String: Any] = ["domain": domain, "raw": rawSnapshot]

      if dumpResolved {

          var resolved: [String: Any] = [:]

          func resolve(fullKey: String, value: Any) -> Any {
            if modeKeys.contains(fullKey) {
              return toPentabool(value).rawValue
            }
            // Parameters: keep exact type (Bool/Number/String)
            if parameterKeys.contains(fullKey) {
              return value
            }
            // Unknown keys: safest default is keep raw (no surprises)
            return value
          }

          for (section, value) in rawSnapshot {
            if let dict = value as? [String: Any] {
              for (k, v) in dict {
                let fk = "\(section).\(k)"
                resolved[fk] = resolve(fullKey: fk, value: v)
              }
            } else {
              // If you ever have non-dict top-level values
              resolved[section] = value
            }
          }

          output["resolved"] = resolved
          output["note"] = "resolved: modeKeys => pentabool (-2..2); parameterKeys/unknown => raw"


      }

      print(ManagedPrefs.toPrettyJSON(output))
      Foundation.exit(0)
    }

    log.info("Runner start (no-op).")
  }
}
