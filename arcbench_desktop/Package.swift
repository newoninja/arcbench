// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArcBenchDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ArcBenchDesktop",
            path: "Sources",
            resources: [
                .copy("Resources/claudelogo.png"),
                .copy("Resources/groklogo.png"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
