import Foundation
import Testing
import TimesheetCore
@testable import LocalModels

@MainActor
@Suite(.serialized)
final class MLXModelManagerTests {
    private let repo = "mlx-community/Tiny-4bit"
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelsTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func tree(_ files: [(String, Int)]) -> Data {
        let entries = files.map { #"{"type":"file","path":"\#($0.0)","size":\#($0.1)}"# }
        return Data("[\(entries.joined(separator: ","))]".utf8)
    }

    private func stubRepo(weights: StubHub.Reply = .init(body: Data("weights".utf8))) {
        StubHub.reset([
            "/api/models/\(repo)/tree/main": .init(body: tree([
                ("config.json", 2), ("tokenizer.json", 2), ("model.safetensors", 7),
                ("README.md", 5), ("chat_template.jinja", 2), ("original.bin", 9),
            ])),
            "/\(repo)/resolve/main/config.json": .init(body: Data("{}".utf8)),
            "/\(repo)/resolve/main/tokenizer.json": .init(body: Data("{}".utf8)),
            "/\(repo)/resolve/main/chat_template.jinja": .init(body: Data("{}".utf8)),
            "/\(repo)/resolve/main/model.safetensors": weights,
        ])
    }

    private func manager() -> MLXModelManager {
        MLXModelManager(directory: directory, session: StubHub.session())
    }

    private func contents(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    @Test func downloadStoresNeededFilesInRepoFolder() async throws {
        stubRepo()
        let manager = manager()
        #expect(!manager.isDownloaded(repo))

        try await manager.download(repo)

        #expect(manager.isDownloaded(repo))
        let folder = directory.appendingPathComponent("mlx-community--Tiny-4bit")
        #expect(contents(folder) == ["chat_template.jinja", "config.json", "model.safetensors", "tokenizer.json"])
        #expect(!StubHub.paths.contains { $0.hasSuffix("README.md") || $0.hasSuffix("original.bin") })
        #expect(manager.progress[repo] == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".downloads").path))
    }

    @Test func failedDownloadLeavesNothingBehind() async throws {
        stubRepo(weights: .init(status: 500))
        let manager = manager()

        await #expect(throws: HubDownloadError.http(500)) { try await manager.download(repo) }

        #expect(!manager.isDownloaded(repo))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("mlx-community--Tiny-4bit").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".downloads").path))
        #expect(manager.progress[repo] == nil)
    }

    @Test func cancelledDownloadLeavesNothingBehind() async throws {
        stubRepo(weights: .init(body: Data("weights".utf8), delay: 5))
        let manager = manager()

        let download = Task { try await manager.download(repo) }
        while manager.progress[repo] == nil { await Task.yield() }
        try await Task.sleep(for: .milliseconds(200))
        manager.cancel(repo)

        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(!manager.isDownloaded(repo))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".downloads").path))
        #expect(manager.progress[repo] == nil)
    }

    @Test func repoWithoutWeightsIsRefused() async throws {
        StubHub.reset(["/api/models/\(repo)/tree/main": .init(body: tree([("config.json", 2)]))])
        let manager = manager()

        await #expect(throws: HubDownloadError.notAModel) { try await manager.download(repo) }
        #expect(!manager.isDownloaded(repo))
    }

    @Test func deleteRemovesTheFolder() async throws {
        stubRepo()
        let manager = manager()
        try await manager.download(repo)

        try manager.delete(repo)

        #expect(!manager.isDownloaded(repo))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("mlx-community--Tiny-4bit").path))
    }

    @Test func folderNeedsConfigAndSafetensors() throws {
        let folder = directory.appendingPathComponent("mlx-community--Tiny-4bit")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manager = manager()
        try Data().write(to: folder.appendingPathComponent("config.json"))
        #expect(!manager.isDownloaded(repo))
        try Data().write(to: folder.appendingPathComponent("model-00001-of-00002.safetensors"))
        #expect(manager.isDownloaded(repo))
    }

    @Test func staleStagingIsClearedOnInit() throws {
        let staging = directory.appendingPathComponent(".downloads/mlx-community--Tiny-4bit")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = manager()
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test func invalidRepoIdsAreRefused() async {
        let manager = manager()
        for id in ["../escape", "a/b/c", "a/..", "noslash", "/b", "a/.hidden"] {
            #expect(!manager.isDownloaded(id))
            await #expect(throws: HubDownloadError.invalidRepoId(id)) { try await manager.download(id) }
        }
    }

    @Test func clientWithoutWeightsIsNotReady() async {
        let client = manager().client(for: repo)
        await #expect(throws: LLMError.modelNotReady) { try await client.complete(system: "s", user: "u") }
    }

    @Test func sameClientUntilDeleted() throws {
        let manager = manager()
        let first = manager.client(for: repo)
        #expect(manager.client(for: repo) === first)
        try manager.delete(repo)
        #expect(manager.client(for: repo) !== first)
    }

    @Test func damagedModelFailsWithReadableError() async throws {
        let folder = directory.appendingPathComponent("mlx-community--Tiny-4bit")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data().write(to: folder.appendingPathComponent("model.safetensors"))
        let client = manager().client(for: repo)
        await #expect(throws: LLMError.modelLoadFailed) { try await client.complete(system: "s", user: "u") }
    }

    @Test func onlyTheLastRequestedClientIsKept() {
        let manager = manager()
        let first = manager.client(for: repo)
        _ = manager.client(for: "mlx-community/Other-4bit")
        #expect(manager.client(for: repo) !== first)
    }

    @Test func releasingClientsDropsTheLoadedOne() {
        let manager = manager()
        let first = manager.client(for: repo)
        manager.releaseClients()
        #expect(manager.client(for: repo) !== first)
    }
}
