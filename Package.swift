// swift-tools-version:5.9
// Swift Package Manager reads the manifest at the repository root, so this
// file exposes the iOS SDK that lives in ios/. Install with:
//   .package(url: "https://github.com/Cross-Indie/sdks.git", from: "1.2.0")
import PackageDescription

let package = Package(
    name: "CrossIndie",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "CrossIndie", targets: ["CrossIndie"]),
    ],
    targets: [
        .target(name: "CrossIndie", path: "ios/Sources/CrossIndie"),
        .testTarget(name: "CrossIndieTests", dependencies: ["CrossIndie"], path: "ios/Tests/CrossIndieTests"),
    ]
)
