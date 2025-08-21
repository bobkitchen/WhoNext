// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoNextDependencies",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    dependencies: [
        // Existing dependencies
        .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.5.0"),
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0"),
        
        // MLX for Apple Silicon
        .package(url: "https://github.com/ml-explore/mlx-swift", branch: "main"),
        
        // MLX Examples (includes Whisper implementation we can adapt)
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
        
        // For model downloading
        .package(url: "https://github.com/huggingface/swift-transformers", branch: "main")
    ],
    targets: [
        .target(
            name: "WhoNextDependencies",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Down", package: "Down"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers")
            ]
        )
    ]
)