// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalModels",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LocalModels", targets: ["LocalModels"]),
    ],
    dependencies: [
        .package(path: "../TimesheetCore"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        // Tokenizers only: loads tokenizer files from the model folder, no network.
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
    ],
    targets: [
        .target(
            name: "LocalModels",
            dependencies: [
                .product(name: "TimesheetCore", package: "TimesheetCore"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]),
        .testTarget(name: "LocalModelsTests", dependencies: ["LocalModels"]),
    ]
)
