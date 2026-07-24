// swift-tools-version: 5.9
// Published from source commit: 7ef9a8f5fc08012e0717df8fbe225d9628c1447c

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.0.2/vck-ios.xcframework.zip",
            checksum: "e05c9d7df88b1afacb5a205b9b70603a68d477ebb9e05123b912a23945c5fffa"
        )
    ]
)
