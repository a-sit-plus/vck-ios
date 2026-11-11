// swift-tools-version: 5.9
// Published from source commit: 5966fb0ef8d4b211b0fad04ec8d81c7e44967351

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.3.0/vck-ios.xcframework.zip",
            checksum: "c181e2f6e21d544518f7f9e70e6425305f62042bd469de3ead979256e512fb25"
        )
    ]
)
