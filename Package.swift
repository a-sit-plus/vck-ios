// swift-tools-version: 5.9
// Published from source commit: fb0ffd2b258b72bf1b0814437a337f628f1991e3

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.2.3/vck-ios.xcframework.zip",
            checksum: "e4164064733e80d92c0e9c1758d4365b958ea1cf1839e9a226ea5b233b303288"
        )
    ]
)
