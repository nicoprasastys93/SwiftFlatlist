// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftFlatlist",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SwiftFlatlist", targets: ["SwiftFlatlist"])
    ],
    targets: [
        .target(name: "SwiftFlatlist"),
        .testTarget(name: "SwiftFlatlistTests", dependencies: ["SwiftFlatlist"])
    ]
)
