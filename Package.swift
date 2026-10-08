// swift-tools-version: 5.9
// Published from source commit: 927c8a6a9f862a85e3ee14babac66b5a04d5a288

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.2.2/vck-ios.xcframework.zip",
            checksum: "39fd323794670ecb4e5e7953d428f50ee68272177e4ed4787cae9c64ca01c721"
        )
    ]
)
