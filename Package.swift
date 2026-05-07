// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevDashboard",
            path: "Sources"
        ),
    ]
)
