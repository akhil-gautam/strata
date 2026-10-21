// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockDock",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "DockDock", targets: ["DockDock"])
    ],
    targets: [
        .executableTarget(
            name: "DockDock",
            path: "Sources/DockDock",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
