// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kaltoe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kaltoe",
            path: "Sources/Kaltoe"
        ),
        .testTarget(
            name: "KaltoeTests",
            dependencies: ["Kaltoe"],
            path: "Tests/KaltoeTests"
        ),
    ]
)
