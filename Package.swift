// swift-tools-version: 5.9
// Published from source commit: 02d7b917e78dc95826e3a9204737696699a775c7

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.1.2/vck-ios.xcframework.zip",
            checksum: "fea973db052215c829f455202293708ec7b16c5197076b900fc94c8faa38cb74"
        )
    ]
)
