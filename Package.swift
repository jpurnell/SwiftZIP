// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftZIP",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SwiftZIP", targets: ["SwiftZIP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib"
        ),
        .target(
            name: "SwiftZIP",
            dependencies: ["CZlib"],
            path: "Sources/SwiftZIP"
        ),
        .testTarget(
            name: "SwiftZIPTests",
            dependencies: ["SwiftZIP"],
            path: "Tests/SwiftZIPTests"
        ),
    ]
)
