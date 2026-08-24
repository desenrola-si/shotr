// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shotr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Shotr",
            path: "Sources/Shotr",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
