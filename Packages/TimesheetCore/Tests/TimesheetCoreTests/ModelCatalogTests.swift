import Testing
@testable import TimesheetCore

struct ModelCatalogTests {
    private let gib: UInt64 = 1 << 30

    @Test func tierFromMemory() {
        #expect(RAMTier.forMemory(bytes: 16 * gib) == .gb16)
        #expect(RAMTier.forMemory(bytes: 32 * gib) == .gb32)
        #expect(RAMTier.forMemory(bytes: 24 * gib - 1) == .gb16)
        #expect(RAMTier.forMemory(bytes: 24 * gib) == .gb32)
        #expect(RAMTier.gb16 < RAMTier.gb32)
    }

    @Test func available16IsTheThreeSmallModels() {
        #expect(ModelCatalog.available(for: .gb16).map(\.id) == [
            "mlx-community/Qwen3-4B-4bit",
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "mlx-community/gemma-4-e4b-it-4bit",
        ])
    }

    @Test func available32IsAllSix() {
        #expect(ModelCatalog.available(for: .gb32) == ModelCatalog.all)
        #expect(Set(ModelCatalog.all.map(\.id)) == [
            "mlx-community/Qwen3-4B-4bit",
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "mlx-community/gemma-4-e4b-it-4bit",
            "mlx-community/Qwen3-8B-4bit",
            "mlx-community/Qwen3-14B-4bit",
            "mlx-community/gemma-3-12b-it-4bit",
        ])
    }

    @Test func gemma4IsInThe16Tier() {
        let gemma = ModelCatalog.all.first { $0.id == "mlx-community/gemma-4-e4b-it-4bit" }
        #expect(gemma?.tier == .gb16)
        #expect(gemma?.displayName == "Gemma 4 E4B")
    }

    @Test func allModelsUseMLX() {
        #expect(ModelCatalog.all.allSatisfy { $0.runtime == .mlx })
    }
}
