import Foundation

/// The memory class of this Mac, which decides which on-device models are offered.
public enum RAMTier: Comparable, Sendable {
    case gb16, gb32

    /// Below 24 GiB counts as a 16 GB Mac; 24 GiB and above as 32 GB.
    public static func forMemory(bytes: UInt64) -> RAMTier {
        bytes < 24 * (1 << 30) ? .gb16 : .gb32
    }
}

public enum ModelRuntime: Equatable, Sendable {
    case mlx
    /// The model can't run on this Mac's runtime yet and is usable only through an endpoint.
    case endpointOnly(reason: String)
}

public struct CatalogModel: Identifiable, Equatable, Sendable {
    /// Hugging Face repo id.
    public let id: String
    public let displayName: String
    /// The smallest tier the model fits in.
    public let tier: RAMTier
    /// Approximate download size in gigabytes.
    public let approxGB: Double
    public let runtime: ModelRuntime

    public init(id: String, displayName: String, tier: RAMTier, approxGB: Double, runtime: ModelRuntime) {
        self.id = id
        self.displayName = displayName
        self.tier = tier
        self.approxGB = approxGB
        self.runtime = runtime
    }
}

/// The on-device models offered in Settings.
public enum ModelCatalog {
    public static let all: [CatalogModel] = [
        CatalogModel(id: "mlx-community/Qwen3-4B-4bit", displayName: "Qwen3 4B",
                     tier: .gb16, approxGB: 2.5, runtime: .mlx),
        CatalogModel(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", displayName: "Llama 3.2 3B Instruct",
                     tier: .gb16, approxGB: 2, runtime: .mlx),
        CatalogModel(id: "mlx-community/gemma-4-e4b-it-4bit", displayName: "Gemma 4 E4B",
                     tier: .gb16, approxGB: 3, runtime: .mlx),
        CatalogModel(id: "mlx-community/Qwen3-8B-4bit", displayName: "Qwen3 8B",
                     tier: .gb32, approxGB: 5, runtime: .mlx),
        CatalogModel(id: "mlx-community/Qwen3-14B-4bit", displayName: "Qwen3 14B",
                     tier: .gb32, approxGB: 8, runtime: .mlx),
        CatalogModel(id: "mlx-community/gemma-3-12b-it-4bit", displayName: "Gemma 3 12B",
                     tier: .gb32, approxGB: 7, runtime: .mlx),
    ]

    /// Models that fit a Mac of the given tier, smallest tier first, in catalog order.
    public static func available(for tier: RAMTier) -> [CatalogModel] {
        all.filter { $0.tier <= tier }
    }
}
