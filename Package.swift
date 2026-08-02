// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Cagong",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cagong",
            path: "Sources/Cagong",
            resources: [
                .copy("Resources/Backgrounds"),
                .copy("Resources/Drinks"),
                .copy("Resources/AppIcon.icns")
            ]
        )
    ]
)
