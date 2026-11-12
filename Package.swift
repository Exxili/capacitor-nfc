// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExxiliCapacitorNfc",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "ExxiliCapacitorNfc",
            targets: ["NFCPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", "6.0.0"..<"9.0.0")
    ],
    targets: [
        .target(
            name: "NFCPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/NFCPlugin")
    ]
)
