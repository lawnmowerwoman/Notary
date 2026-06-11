// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "NotaryRunner",
  platforms: [
    .macOS(.v12)
  ],
  products: [
    .library(
      name: "NotaryCore",
      targets: ["NotaryCore"]
    ),
    .executable(
      name: "notary",
      targets: ["notary"]
    ),
    .executable(
      name: "NotaryApp",
      targets: ["NotaryApp"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "NotaryCore",
      path: "Sources/NotaryRunner",
      exclude: [
        "Service",
        "UI"
      ],
      sources: [
        "Core",
        "GeneratedKeys.swift",
        "Version.generated.swift"
      ]
    ),
    .executableTarget(
      name: "notary",
      dependencies: [
        "NotaryCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/NotaryRunner/Service"
    ),
    .executableTarget(
      name: "NotaryApp",
      dependencies: [
        "NotaryCore"
      ],
      path: "Sources/NotaryRunner/UI"
    )
  ]
)
