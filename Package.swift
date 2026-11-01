// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LookupWord",
    platforms: [.macOS(.v14)],  // SCScreenshotManager
    targets: [
        .executableTarget(name: "LookupWord", path: "Sources/LookupWord"),
    ]
)
