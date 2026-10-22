import Foundation

/// Downloads, deletes and hands out on-device models stored under one directory.
///
/// A model is stored in `<directory>/<org>--<name>/`. A download is staged elsewhere and moved
/// into place only when complete, so a failed or cancelled download never looks downloaded.
@MainActor
public final class MLXModelManager: ObservableObject {
    /// Fraction done (0...1) for each model being downloaded; absent when not downloading.
    @Published public private(set) var progress: [String: Double] = [:]

    private let directory: URL
    private let downloader: HubDownloader
    private var downloads: [String: (token: UUID, task: Task<Void, Error>)] = [:]
    private var clients: [String: MLXClient] = [:]

    public convenience init(directory: URL) {
        self.init(directory: directory, session: .shared)
    }

    init(directory: URL, session: URLSession) {
        self.directory = directory
        self.downloader = HubDownloader(session: session)
        // Leftovers from a download interrupted by a quit or crash.
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(ModelStorage.stagingFolderName, isDirectory: true))
    }

    public func isDownloaded(_ id: String) -> Bool {
        ModelStorage.isValidRepoId(id) && ModelStorage.isComplete(ModelStorage.folder(for: id, in: directory))
    }

    /// Downloads the model's weights, configs and tokenizer files. Does nothing if it is already downloading.
    /// Throws `CancellationError` after `cancel(_:)`.
    public func download(_ id: String) async throws {
        guard downloads[id] == nil else { return }
        guard ModelStorage.isValidRepoId(id) else { throw HubDownloadError.invalidRepoId(id) }
        let fileManager = FileManager.default
        let staging = ModelStorage.stagingFolder(for: id, in: directory)
        let destination = ModelStorage.folder(for: id, in: directory)

        let token = UUID()
        let downloader = downloader
        let task = Task.detached { [weak self] in
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try await downloader.download(repoId: id, into: staging) { fraction in
                Task { @MainActor in self?.report(fraction, for: id, token: token) }
            }
        }
        downloads[id] = (token, task)
        progress[id] = 0
        defer {
            downloads[id] = nil
            progress[id] = nil
            let stagingRoot = staging.deletingLastPathComponent()
            if (try? fileManager.contentsOfDirectory(atPath: stagingRoot.path))?.isEmpty == true {
                try? fileManager.removeItem(at: stagingRoot)
            }
        }

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            if task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    public func cancel(_ id: String) {
        downloads[id]?.task.cancel()
    }

    /// Removes the model's folder. Deleting a model that isn't downloaded does nothing.
    public func delete(_ id: String) throws {
        guard ModelStorage.isValidRepoId(id) else { return }
        clients[id] = nil
        let folder = ModelStorage.folder(for: id, in: directory)
        objectWillChange.send()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// The client for a model. The same client is returned until the model is deleted or another model is
    /// asked for, so it stays loaded; only one model is kept in memory at a time.
    public func client(for id: String) -> MLXClient {
        if let client = clients[id] { return client }
        let client = MLXClient(directory: ModelStorage.folder(for: id, in: directory))
        clients = [id: client]
        return client
    }

    /// Drops every client, freeing its loaded model once no compile still uses it.
    public func releaseClients() {
        clients = [:]
    }

    private func report(_ fraction: Double, for id: String, token: UUID) {
        // Late updates from a finished or replaced download are dropped.
        guard downloads[id]?.token == token else { return }
        // Skip tiny steps so the UI isn't redrawn for every network chunk.
        if let current = progress[id], fraction < 1, fraction - current < 0.002 { return }
        progress[id] = fraction
    }
}
