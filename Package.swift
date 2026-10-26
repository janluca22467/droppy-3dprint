// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrintLive",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PrintLive", type: .dynamic, targets: ["PrintLive"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.19.0")
    ],
    targets: [
        .target(
            name: "PrintLive",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .executableTarget(
            name: "PrintLiveHarness",
            dependencies: [
                "PrintLive",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
