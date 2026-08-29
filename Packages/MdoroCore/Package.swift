// swift-tools-version: 6.3

import PackageDescription

// REQ-PRT-001: the state machine, the wire protocol and the data models must not exist twice,
// once for the Mac and once for the iPhone. Anything that can be shared lives in this package.
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
