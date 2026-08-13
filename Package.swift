// swift-tools-version: 5.9
// Published from source commit: 3f8084bc93df0df48cc120c54a521d378d280852

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.1.0/vck-ios.xcframework.zip",
            checksum: "05fce5148c000c2ddb629be65480319d86e5cfe466b615478a0c047d7a26842f"
        )
    ]
)
