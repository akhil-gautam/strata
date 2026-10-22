// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Strata", targets: ["Strata"])
    ],
    targets: [
        .executableTarget(
            name: "Strata",
            path: "Sources/Strata",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
