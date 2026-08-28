// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacKeyClean",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MacKeyClean", path: "Sources/MacKeyClean")
    ]
)
