// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Floater",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloaterCore", targets: ["FloaterCore"]),
        .executable(name: "Floater", targets: ["Floater"]),
    ],
    targets: [
        .target(
            name: "FloaterCore",
            path: "Sources/FloaterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Floater",
            dependencies: ["FloaterCore"],
            path: "Sources/Floater",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FloaterCoreTests",
            dependencies: ["FloaterCore"],
            path: "Tests/FloaterCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
