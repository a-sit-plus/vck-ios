// swift-tools-version: 5.9
// Published from source commit: 8d77eec168259b0df74a2d7f1d77ac651e9e51ff

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
            url: "https://github.com/a-sit-plus/vck-ios/releases/download/1.1.1/vck-ios.xcframework.zip",
            checksum: "69509d859f46c3ad5f30f230d84af69317883bc9fc3710cab8d4e93cc3a07aab"
        )
    ]
)
