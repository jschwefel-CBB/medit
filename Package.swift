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
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0"),
        // Markdown parsing (Apple, CommonMark + GFM). swift-markdown publishes no
        // semver tags — it tracks the toolchain — so we pin an exact revision in
        // the manifest for reproducible builds (resolves against Swift 6.3).
        // To advance: `swift package update swift-markdown`, then update this SHA
        // to the new Package.resolved revision.
        .package(url: "https://github.com/apple/swift-markdown.git",
                 revision: "4661b550c55abde97d14e35b89e094084669f40a")
    ],
    targets: [
        .target(
            name: "MeditKit",
            dependencies: [
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "Markdown", package: "swift-markdown")
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
