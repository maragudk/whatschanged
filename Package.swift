// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhatsChanged",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "WhatsChanged",
            path: "Sources/WhatsChanged"
        ),
    ]
)
