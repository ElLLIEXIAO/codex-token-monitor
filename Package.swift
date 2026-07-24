// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexTokenMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexTokenMonitor", targets: ["CodexTokenMonitor"])
    ],
    targets: [
        .executableTarget(name: "CodexTokenMonitor")
    ]
)
