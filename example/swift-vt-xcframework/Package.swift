// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-vt-xcframework",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "swift-vt-xcframework",
            dependencies: ["VoidVt"],
            path: "Sources"
        ),
        .binaryTarget(
            name: "VoidVt",
            path: "../../zig-out/lib/void-vt.xcframework"
        ),
    ]
)
