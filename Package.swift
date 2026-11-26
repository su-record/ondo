// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ondo",
    platforms: [.macOS(.v13)],
    targets: [
        // SMC and HID sensor access in C: the struct layouts must match the kernel exactly.
        .target(name: "CSensors"),
        .target(name: "OndoSensors", dependencies: ["CSensors"]),
        .target(name: "OndoCore", dependencies: ["OndoSensors", "OndoShared"]),
        .target(name: "OndoShared"),
        .executableTarget(name: "OndoApp", dependencies: ["OndoCore", "OndoSensors", "OndoShared"]),
        .executableTarget(name: "OndoHelper", dependencies: ["OndoShared"]),
        .executableTarget(name: "ondo", dependencies: ["OndoCore", "OndoSensors"], path: "Sources/OndoCLI"),
        .testTarget(name: "OndoCoreTests", dependencies: ["OndoCore"]),
        .testTarget(name: "OndoSensorsTests", dependencies: ["OndoSensors"]),
    ],
    swiftLanguageModes: [.v5]
)
