// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevDashboard",
            path: "Sources"
        ),
        .testTarget(
            name: "DevDashboardTests",
            dependencies: ["DevDashboard"],
            path: "Tests"
        ),
    ]
)
