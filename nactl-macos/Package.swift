// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nactl",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "nactl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreLocation"),
            ]
        ),
    ]
)
