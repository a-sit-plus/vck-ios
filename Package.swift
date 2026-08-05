// swift-tools-version: 5.9
// Published from source commit: acb32eb498fc5f22ae13d127c168cc9d02dbdb88

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.0.5/vck-ios.xcframework.zip",
            checksum: "9fa0371511d50ae212292755a304bc1ebcb8f248ecfdb04fc0b6eb9419afb529"
        )
    ]
)
