// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "IgSnap",
    platforms: [.macOS("27.0")],
    targets: [
        // No AppKit: geometry, window hit-testing, annotations and rendering. Host tests.
        .target(name: "IgSnapCore"),
        .testTarget(name: "IgSnapCoreTests", dependencies: ["IgSnapCore"]),
        // The app. `just app` wraps the binary into IgSnap.app.
        // Swift 5 mode: AppKit event handlers and ScreenCaptureKit callbacks without Sendable ceremony.
        .executableTarget(
            name: "IgSnap", dependencies: ["IgSnapCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
