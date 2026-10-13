// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Air7Menu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Air7Menu", targets: ["Air7Menu"])],
    targets: [
        .executableTarget(name: "Air7Menu", path: "Sources/Air7Menu"),
        .testTarget(name: "Air7MenuTests", dependencies: ["Air7Menu"], path: "Tests/Air7MenuTests")
    ],
    swiftLanguageModes: [.v5]
)
