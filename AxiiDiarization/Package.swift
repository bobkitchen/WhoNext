// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AxiiDiarization",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AxiiDiarization",
            targets: ["AxiiDiarization"]
        )
    ],
    targets: [
        .target(
            name: "AxiiDiarization",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate")
            ]
        )
    ]
)
