// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyOnScreenShot",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "CopyOnScreenShot", targets: ["CopyOnScreenShot"])
    ],
    targets: [
        .executableTarget(
            name: "CopyOnScreenShot",
            path: "Sources/CopyOnScreenShot"
        )
    ]
)
