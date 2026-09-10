// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let environment = Context.environment
let requestedTransportImplementation = environment["NOTARY_TRANSPORT_IMPLEMENTATION"] ?? "public"
let confidentialTransportPath = environment["NOTARY_CONFIDENTIAL_TRANSPORT_PATH"] ?? ""
let requestedReporterImplementation = environment["NOTARY_REPORTER_IMPLEMENTATION"] ?? "public"
let confidentialReporterPath = environment["NOTARY_CONFIDENTIAL_REPORTER_PATH"] ?? ""
let localAppTokenGeneratorPath = environment["NOTARY_LOCAL_APP_TOKEN_GENERATOR_PATH"] ?? ""

let usesConfidentialTransport: Bool
let transportDependencies: [Package.Dependency]
let transportTargets: [Target]
let transportDependency: Target.Dependency

switch requestedTransportImplementation {
case "public", "dummy":
  usesConfidentialTransport = false
  transportDependencies = []
  transportTargets = [
    .target(
      name: "NotaryTransportImplementation",
      path: "Sources/NotaryTransportImplementation"
    )
  ]
  transportDependency = "NotaryTransportImplementation"
case "confidential":
  guard !confidentialTransportPath.isEmpty else {
    fatalError("NOTARY_TRANSPORT_IMPLEMENTATION=confidential requires NOTARY_CONFIDENTIAL_TRANSPORT_PATH")
  }
  usesConfidentialTransport = true
  transportDependencies = [
    .package(path: confidentialTransportPath)
  ]
  transportTargets = []
  transportDependency = .product(name: "NotaryTransportImplementation", package: "NotaryConfidentialTransport")
default:
  fatalError("Unsupported NOTARY_TRANSPORT_IMPLEMENTATION value: \(requestedTransportImplementation)")
}

print("Transport implementation: \(usesConfidentialTransport ? "confidential" : "public dummy")")

let usesConfidentialReporter: Bool
let reporterTargets: [Target]
let reporterDependency: Target.Dependency = "NotaryReporterImplementation"

switch requestedReporterImplementation {
case "public", "dummy":
  usesConfidentialReporter = false
  reporterTargets = [
    .target(
      name: "NotaryReporterImplementation",
      dependencies: [
        "NotaryCore",
        "NotaryAboutUI"
      ],
      path: "Sources/NotaryReporterImplementation"
    )
  ]
case "confidential":
  guard !confidentialReporterPath.isEmpty else {
    fatalError("NOTARY_REPORTER_IMPLEMENTATION=confidential requires NOTARY_CONFIDENTIAL_REPORTER_PATH")
  }
  usesConfidentialReporter = true
  reporterTargets = [
    .target(
      name: "NotaryReporterImplementation",
      dependencies: [
        "NotaryCore",
        "NotaryAboutUI"
      ],
      path: confidentialReporterPath
    )
  ]
default:
  fatalError("Unsupported NOTARY_REPORTER_IMPLEMENTATION value: \(requestedReporterImplementation)")
}

print("Reporter implementation: \(usesConfidentialReporter ? "confidential" : "public dummy")")

let notaryCoreSwiftSettings: [SwiftSetting] = usesConfidentialReporter ? [
  .define("NOTARY_CONFIDENTIAL_REPORTER")
] : []

let usesLocalAppTokenGenerator = !localAppTokenGeneratorPath.isEmpty
if usesLocalAppTokenGenerator {
  print("App Token Generator: local confidential")
}

let appTokenGeneratorProducts: [Product] = usesLocalAppTokenGenerator ? [
  .executable(
    name: "apptoken",
    targets: ["apptoken"]
  ),
  .executable(
    name: "AppTokenGeneratorApp",
    targets: ["AppTokenGeneratorApp"]
  )
] : []

let appTokenGeneratorTargets: [Target] = usesLocalAppTokenGenerator ? [
  .target(
    name: "AppTokenGeneratorSupport",
    dependencies: [
      "AppTokenKit"
    ],
    path: "\(localAppTokenGeneratorPath)/Support"
  ),
  .executableTarget(
    name: "apptoken",
    dependencies: [
      "AppTokenKit",
      "AppTokenGeneratorSupport",
      .product(name: "ArgumentParser", package: "swift-argument-parser")
    ],
    path: "\(localAppTokenGeneratorPath)/CLI"
  ),
  .executableTarget(
    name: "AppTokenGeneratorApp",
    dependencies: [
      "AppTokenKit",
      "AppTokenGeneratorSupport"
    ],
    path: "\(localAppTokenGeneratorPath)/App"
  )
] : []

let package = Package(
  name: "NotaryRunner",
  platforms: [
    .macOS(.v12)
  ],
  products: [
    .library(
      name: "AppTokenKit",
      targets: ["AppTokenKit"]
    ),
    .library(
      name: "NotaryCore",
      targets: ["NotaryCore"]
    ),
    .executable(
      name: "apptoken-tests",
      targets: ["apptoken-tests"]
    ),
    .executable(
      name: "transport-tests",
      targets: ["transport-tests"]
    ),
    .executable(
      name: "notary",
      targets: ["notary"]
    ),
    .executable(
      name: "NotaryApp",
      targets: ["NotaryApp"]
    ),
    .executable(
      name: "notarystatus",
      targets: ["notarystatus"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
  ] + transportDependencies,
  targets: [
    .target(
      name: "AppTokenKit",
      path: "Sources/AppTokenKit"
    ),
    .target(
      name: "NotaryCore",
      dependencies: [
        "AppTokenKit"
      ],
      path: "Sources/NotaryRunner",
      exclude: [
        "Service",
        "Status",
        "UI"
      ],
      sources: [
        "Core",
        "GeneratedKeys.swift",
        "Version.generated.swift"
      ],
      swiftSettings: notaryCoreSwiftSettings
    ),
    .target(
      name: "NotaryAboutUI",
      dependencies: [
        "NotaryCore"
      ],
      path: "Sources/NotaryAboutUI"
    ),
    .executableTarget(
      name: "notary",
      dependencies: [
        "NotaryCore",
        transportDependency,
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/NotaryRunner/Service"
    ),
    .executableTarget(
      name: "NotaryApp",
      dependencies: [
        "NotaryCore",
        "NotaryAboutUI",
        reporterDependency
      ],
      path: "Sources/NotaryRunner/UI"
    ),
    .executableTarget(
      name: "notarystatus",
      dependencies: [
        "NotaryCore"
      ],
      path: "Sources/NotaryRunner/Status"
    ),
    .executableTarget(
      name: "apptoken-tests",
      dependencies: ["AppTokenKit"],
      path: "Tests/AppTokenKitTests",
      resources: [
        .copy("Fixtures")
      ]
    ),
    .executableTarget(
      name: "transport-tests",
      dependencies: [
        "AppTokenKit",
        "NotaryCore",
        transportDependency
      ],
      path: "Tests/TransportTests"
    )
  ] + transportTargets + reporterTargets + appTokenGeneratorTargets
)

package.products.append(contentsOf: appTokenGeneratorProducts)
