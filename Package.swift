// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fold",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Fold", targets: ["Fold"])],
    targets: [
        .executableTarget(name: "Fold"),
        .testTarget(name: "FoldTests", dependencies: ["Fold"])
    ]
)
