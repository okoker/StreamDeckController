// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreamDeckController",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "StreamDeckController", path: "Sources/VSDDaemon")
    ]
)
