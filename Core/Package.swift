// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyGymHelperCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "MyGymHelperCore", targets: ["MyGymHelperCore"])
    ],
    targets: [
        .target(name: "MyGymHelperCore"),
        .testTarget(name: "MyGymHelperCoreTests", dependencies: ["MyGymHelperCore"])
    ],
    swiftLanguageModes: [.v5]
)
