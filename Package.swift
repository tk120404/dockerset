// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dockerset",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Dockerset", path: "Sources/Dockerset")
    ]
)
