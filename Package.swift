// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LangCycle",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, AppKit-free logic (cycle selection, short codes, names) — unit tested.
        .target(name: "LangCycleCore"),
        // The menu bar app: Carbon hotkeys, TIS wrapper, HUD, menu.
        .executableTarget(name: "LangCycle", dependencies: ["LangCycleCore"]),
        .testTarget(name: "LangCycleCoreTests", dependencies: ["LangCycleCore"]),
    ],
    // Everything runs on the main thread; Swift 5 mode avoids strict-concurrency ceremony around Carbon C callbacks.
    swiftLanguageModes: [.v5]
)
