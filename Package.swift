// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic (history, shortcut model) — no AppKit, fully unit-tested.
        .target(name: "ClipStackCore", path: "Sources/ClipStackCore"),
        // The menu bar app.
        .executableTarget(name: "ClipStack", dependencies: ["ClipStackCore"], path: "Sources/ClipStack"),
        .testTarget(name: "ClipStackCoreTests", dependencies: ["ClipStackCore"], path: "Tests/ClipStackCoreTests"),
    ]
)
