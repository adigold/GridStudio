// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GridStudio",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "GridStudio",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/GridStudio",
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("IOKit"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
