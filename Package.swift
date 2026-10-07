// swift-tools-version: 5.9
// Published from source commit: 91a4767cbabfd30509a013d3ae2fb3eb01e65558

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.2.1/vck-ios.xcframework.zip",
            checksum: "ae4e761e7484b943beedcbfea9e57e96dd45c53ed33ea37f6f5b595755c736ea"
        )
    ]
)
