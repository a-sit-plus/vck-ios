// swift-tools-version: 5.9
// Published from source commit: a984b919505a855a9c8a4781cf5c1a5d9cd9e39d

import PackageDescription

let package = Package(
    name: "vck-ios",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "vck-ios",
            targets: ["vck_ios"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "vck_ios",
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.0.3/vck-ios.xcframework.zip",
            checksum: "8ff4599bdb2276c2f1e20e580ab46708e1ceb44971bd4c6931b7ade515a18580"
        )
    ]
)
