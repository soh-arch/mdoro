// swift-tools-version: 6.3

import PackageDescription

// REQ-PRT-001: Mac 版と iPhone 版で状態機械・通信プロトコル・データモデルを二重に実装しない。
// 共有できるコードはすべてこのパッケージに置く。
let package = Package(
    name: "MdoroCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "MdoroCore",
            targets: ["MdoroCore"]
        ),
    ],
    targets: [
        .target(
            name: "MdoroCore"
        ),
        .testTarget(
            name: "MdoroCoreTests",
            dependencies: ["MdoroCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
