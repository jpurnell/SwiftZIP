// swift-tools-version: 6.2
// legibility:description: Pure-Swift ZIP archive reader and writer.

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
            path: "Sources/SwiftZIP",
            resources: [
                // Declared explicitly. An undeclared .docc trips SwiftPM's
                // "unhandled files" warning, and `exclude:` would silence that by
                // dropping the catalogue from the built documentation — green gate,
                // hollow docs. See docc_guidelines Pitfall 7.
                .copy("SwiftZIP.docc")
            ]
        ),
        .testTarget(
            name: "SwiftZIPTests",
            dependencies: ["SwiftZIP"],
            path: "Tests/SwiftZIPTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
