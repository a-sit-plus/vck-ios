// swift-tools-version: 5.9
// Published from source commit: 0ff9e2580486dba0a854c7694af55e86d22b598e

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.0.4/vck-ios.xcframework.zip",
            checksum: "cab2747f085d49ef17c736ac6b3732159b6287621487862896146498809c251d"
        )
    ]
)
