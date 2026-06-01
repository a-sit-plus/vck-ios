// swift-tools-version: 5.9
// Published from source commit: 94b368ce75256aacb7dd33e4d3e5d45320a7fbac

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/0.0.1/vck-ios.xcframework.zip",
            checksum: "5e7e291f92a5704f1a6e3b9126f7afbcd78e2e79d3d3b4ad10fb290f9545149f"
        )
    ]
)
