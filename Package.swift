// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sofia",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Sofia", targets: ["Sofia"])],
    targets: [
        .target(name: "SofiaCore"),
        .systemLibrary(name: "CSherpa"),
        .executableTarget(name: "Sofia", dependencies: ["SofiaCore", "CSherpa"]),
        .testTarget(name: "SofiaCoreTests", dependencies: ["SofiaCore"]),
    ]
)
