// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepSeekHarnessDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DeepSeekHarnessDesktop", targets: ["DeepSeekHarnessDesktop"]),
        .library(name: "DeepSeekHarnessCore", targets: ["DeepSeekHarnessCore"])
    ],
    targets: [
        .target(name: "DeepSeekHarnessCore"),
        .executableTarget(name: "DeepSeekHarnessDesktop", dependencies: ["DeepSeekHarnessCore"]),
        .testTarget(name: "DeepSeekHarnessCoreTests", dependencies: ["DeepSeekHarnessCore"])
    ]
)
