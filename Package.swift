// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fold",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Fold", targets: ["Fold"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "Fold",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "FoldTests", dependencies: ["Fold"])
    ]
)
