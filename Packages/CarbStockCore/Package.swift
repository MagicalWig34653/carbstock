// swift-tools-version: 6.0
import PackageDescription

// Pure domain logic (spec section 3): no UI, no persistence, no system clock.
let package = Package(
    name: "CarbStockCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "CarbStockCore", targets: ["CarbStockCore"])],
    targets: [
        .target(name: "CarbStockCore"),
        .testTarget(name: "CarbStockCoreTests", dependencies: ["CarbStockCore"]),
    ]
)
