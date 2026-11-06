// swift-tools-version: 6.2
// Логика IPCHEK без интерфейса: всё, что можно проверить тестами без запуска приложения.

import PackageDescription

let strict: [SwiftSetting] = [
  .treatAllWarnings(as: .error)
]

let package = Package(
  name: "IPCheckCore",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "IPCheckCore", targets: ["IPCheckCore"])
  ],
  targets: [
    .target(name: "IPCheckCore", swiftSettings: strict),
    .testTarget(
      name: "IPCheckCoreTests",
      dependencies: ["IPCheckCore"],
      swiftSettings: strict
    ),
  ]
)
