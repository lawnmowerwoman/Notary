#!/usr/bin/env swift
import Foundation

let defaultKeyDirectory = ("~/.ministryofcode/apptoken/keys" as NSString).expandingTildeInPath

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: gen_app_token_public_keys.swift <output.swift> [key-directory]\n", stderr)
    exit(2)
}

let outputPath = CommandLine.arguments[1]
let keyDirectory = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : defaultKeyDirectory
let fileManager = FileManager.default

func base64URLDecode(_ text: String) -> Data? {
    var value = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let padding = value.count % 4
    if padding > 0 {
        value += String(repeating: "=", count: 4 - padding)
    }
    return Data(base64Encoded: value)
}

func keyId(for url: URL) -> String {
    let name = url.lastPathComponent
    if name.hasSuffix(".ed25519.public") {
        return String(name.dropLast(".ed25519.public".count))
    }
    if name.hasSuffix(".public") {
        return String(name.dropLast(".public".count))
    }
    return url.deletingPathExtension().lastPathComponent
}

func swiftString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let encoded = String(decoding: data, as: UTF8.self)
    return String(encoded.dropFirst().dropLast())
}

func swiftData(_ data: Data) -> String {
    "Data([" + data.map { String($0) }.joined(separator: ", ") + "])"
}

let directoryURL = URL(fileURLWithPath: keyDirectory, isDirectory: true)
let urls = (try? fileManager.contentsOfDirectory(
    at: directoryURL,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)) ?? []

var entries: [(keyId: String, data: Data)] = []
for url in urls where url.pathExtension == "public" {
    let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    guard let data = base64URLDecode(raw), data.count == 32 else {
        fputs("warning: ignoring invalid AppToken public key at \(url.path)\n", stderr)
        continue
    }
    entries.append((keyId: keyId(for: url), data: data))
}

entries.sort { $0.keyId < $1.keyId }

if entries.isEmpty {
    fputs("""
warning:
no trusted public keys found

feature-gated capabilities will remain disabled

build completed successfully

""", stderr)
}

let rawKeysLiteral: String
if entries.isEmpty {
    rawKeysLiteral = "[:]"
} else {
    let dictionaryEntries = entries.map { entry in
        "        \(swiftString(entry.keyId)): \(swiftData(entry.data)),"
    }.joined(separator: "\n")
    rawKeysLiteral = "[\n\(dictionaryEntries)\n        ]"
}

let body = """
// AUTO-GENERATED. DO NOT EDIT.
// Generated from local AppToken public keys during the build.

import Foundation

public enum AppTokenEmbeddedPublicKeys {
    public static var registry: PublicKeyRegistry {
        PublicKeyRegistry(rawKeys: rawKeys)
    }

    public static var rawKeys: [String: Data] {
        \(rawKeysLiteral)
    }
}
"""

try fileManager.createDirectory(
    at: URL(fileURLWithPath: outputPath).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try body.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
print("Wrote \(outputPath)")
