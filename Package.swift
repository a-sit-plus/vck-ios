// swift-tools-version: 5.9
// Published from source commit: 5e42eecf9c30536a6bd931afa1dd6e7cedd6c9d2

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.0.1/vck-ios.xcframework.zip",
            checksum: "6a06de731c99c5706af5ac7ae2591596577e5c1759c2983b2b1b90b9e83fec03"
        )
    ]
)
