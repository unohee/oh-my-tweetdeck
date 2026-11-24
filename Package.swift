// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhMyTweetDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OhMyTweetDeck", targets: ["OhMyTweetDeck"]),
        .library(name: "OhMyTweetDeckCore", targets: ["OhMyTweetDeckCore"]),
    ],
    targets: [
        // UI-free logic: services, columns, text limits, publishers. Fully unit-tested.
        .target(name: "OhMyTweetDeckCore"),
        // SwiftUI + WKWebView app shell. Wrapped into a .app by scripts/build-app.sh.
        .executableTarget(
            name: "OhMyTweetDeck",
            dependencies: ["OhMyTweetDeckCore"]
        ),
        .testTarget(
            name: "OhMyTweetDeckCoreTests",
            dependencies: ["OhMyTweetDeckCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
