// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeditKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MeditKit",
            targets: ["MeditKit"]
        )
    ],
    dependencies: [
        // Syntax highlighting via highlight.js. HighlighterSwift's product/import
        // name is `Highlighter` (the package repo is HighlighterSwift).
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0")
    ],
    targets: [
        .target(
            name: "MeditKit",
            dependencies: [
                .product(name: "Highlighter", package: "HighlighterSwift")
            ],
            swiftSettings: [
                // Start in Swift 5 language mode. AppKit's delegate-heavy, main-thread
                // API surface produces a large volume of strict-concurrency diagnostics
                // under Swift 6; we opt into v6 incrementally once the app runs.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MeditKitTests",
            dependencies: ["MeditKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
