// swift-tools-version: 5.9
// Published from source commit: 843a97c08cea8ba9f154d0a9846dbc12d0001ee2

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.2.0/vck-ios.xcframework.zip",
            checksum: "fc25d74f736185d9d43882a7ded38bce79be31ce7e6ab3fbc5ae661a91296716"
        )
    ]
)
