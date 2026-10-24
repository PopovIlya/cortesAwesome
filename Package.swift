// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cortes",
    platforms: [.macOS(.v14)],
    dependencies: [
        // On-device speech recognition for calls; Apple's own recogniser has no on-device Russian.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "CortesCore", path: "Sources/CortesCore", resources: [.copy("Resources/voices.json")]),
        .executableTarget(name: "Cortes", dependencies: ["CortesCore", .product(name: "WhisperKit", package: "WhisperKit")],
                         path: "Sources/Cortes"),
        .testTarget(name: "CortesTests", dependencies: ["CortesCore"], path: "Tests/CortesTests"),
    ]
)
