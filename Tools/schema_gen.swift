#!/usr/bin/env swift
import Foundation

let directives: Set<String> = [
  "hard-enforce", "enforce", "off", "check", "hard-check",
  "1", "0", "-1", "-2", "true", "false", "yes", "no", "on"
]

func loadJSON(_ path: String) throws -> Any {
  let url = URL(fileURLWithPath: path)
  let data = try Data(contentsOf: url)
  return try JSONSerialization.jsonObject(with: data, options: [])
}

func asDict(_ any: Any) -> [String: Any]? { any as? [String: Any] }

func enumIsDirectiveOnly(_ node: [String: Any]) -> Bool {
  guard let arr = node["enum"] as? [Any], !arr.isEmpty else { return false }
  let vals = arr.map { String(describing: $0).lowercased() }
  return vals.allSatisfy { directives.contains($0) }
}

func nodeType(_ node: [String: Any]) -> String? {
  if let t = node["type"] as? String { return t }
  // Sometimes type is array (rare here) – keep simple
  return nil
}

struct Result {
  var topKeys: [String] = []
  var modeKeys: Set<String> = []
  var parameterKeys: Set<String> = []
}

func walkProperties(prefix: String?, properties: [String: Any], res: inout Result) {
  for (key, rawNode) in properties.sorted(by: { $0.key < $1.key }) {
    guard let node = asDict(rawNode) else { continue }
    let fullKey = prefix == nil ? key : "\(prefix!).\(key)"

    if prefix == nil {
      res.topKeys.append(key)
    }

    if let t = nodeType(node) {
      if t == "object" {
        if let childProps = node["properties"] as? [String: Any] {
          walkProperties(prefix: fullKey, properties: childProps, res: &res)
        }
        continue
      }

      if t == "string" {
        if enumIsDirectiveOnly(node) {
          res.modeKeys.insert(fullKey)
        } else {
          res.parameterKeys.insert(fullKey)
        }
        continue
      }

      if t == "integer" || t == "number" || t == "boolean" {
        // All scalar non-string directive fields are parameters in your model
        res.parameterKeys.insert(fullKey)
        continue
      }
    }

    // Fallback: treat unknown as parameter (safe)
    res.parameterKeys.insert(fullKey)
  }
}

func swiftStringArray(_ arr: [String]) -> String {
  let items = arr.map { "    \"\($0)\"," }.joined(separator: "\n")
  return "[\n\(items)\n  ]"
}

func swiftStringSet(_ set: Set<String>) -> String {
  let items = set.sorted().map { "    \"\($0)\"," }.joined(separator: "\n")
  return "Set([\n\(items)\n  ])"
}

guard CommandLine.arguments.count >= 3 else {
  fputs("Usage: schema_gen.swift <schema.json> <output.swift>\n", stderr)
  exit(2)
}

let schemaPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

let rootAny = try loadJSON(schemaPath)
guard let root = asDict(rootAny),
      let props = root["properties"] as? [String: Any] else {
  fputs("Invalid schema: missing root.properties\n", stderr)
  exit(3)
}

var res = Result()
walkProperties(prefix: nil, properties: props, res: &res)

let header = """
// AUTO-GENERATED. DO NOT EDIT.
// Generated from \(URL(fileURLWithPath: schemaPath).lastPathComponent)

import Foundation

package enum GeneratedKeys {
  package static let topKeys: [String] = \(swiftStringArray(res.topKeys))

  package static let modeKeys: Set<String> = \(swiftStringSet(res.modeKeys))

  package static let parameterKeys: Set<String> = \(swiftStringSet(res.parameterKeys))
}
"""

try header.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
print("Wrote \(outPath)")
