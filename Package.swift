// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shelfie",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Shelfie", targets: ["Shelfie"])
    ],
    targets: [
        .executableTarget(
            name: "Shelfie",
            path: "Sources/Shelfie",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
