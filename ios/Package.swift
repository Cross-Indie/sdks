// swift-tools-version:5.9
// Local development manifest for the iOS SDK (`cd ios && swift test`).
// Apps install from the repo-root Package.swift (same sources).
import PackageDescription

let package = Package(
    name: "CrossIndie",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "CrossIndie", targets: ["CrossIndie"]),
    ],
    targets: [
        .target(name: "CrossIndie", path: "Sources/CrossIndie", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "CrossIndieTests", dependencies: ["CrossIndie"], path: "Tests/CrossIndieTests"),
    ]
)
