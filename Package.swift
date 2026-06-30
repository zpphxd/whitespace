// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whitespace",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Whitespace",
            path: "Sources/Whitespace"
        )
    ]
)
