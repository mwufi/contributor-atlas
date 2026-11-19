// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContributorAtlas",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ContributorAtlas", targets: ["ContributorAtlas"])],
    targets: [
        .target(name: "AtlasCore"),
        .executableTarget(name: "ContributorAtlas", dependencies: ["AtlasCore"]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"])
    ],
    swiftLanguageModes: [.v5]
)
