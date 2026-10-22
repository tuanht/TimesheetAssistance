import Foundation

enum HubDownloadError: LocalizedError, Equatable {
    case invalidRepoId(String)
    case http(Int)
    /// The repo lists no `config.json` or no `*.safetensors` file.
    case notAModel

    var errorDescription: String? {
        switch self {
        case .invalidRepoId(let id): "“\(id)” isn’t a Hugging Face model id."
        case .http(let status): "Hugging Face returned HTTP \(status)."
        case .notAModel: "The Hugging Face repo has no MLX model files."
        }
    }
}

/// Downloads the files a model needs from Hugging Face into a folder, reporting overall progress.
struct HubDownloader: Sendable {
    struct RepoFile: Decodable, Equatable, Sendable {
        let type: String
        let path: String
        let size: Int64
    }

    static let base = URL(string: "https://huggingface.co")!

    let session: URLSession

    /// Top-level weights, configs, tokenizer files and chat templates; the rest of the repo is skipped.
    static func neededFiles(_ files: [RepoFile]) -> [RepoFile] {
        files.filter { file in
            file.type == "file" && !file.path.contains("/")
                && [".safetensors", ".json", ".jinja"].contains { file.path.hasSuffix($0) }
        }
    }

    /// Downloads every needed file of `repoId` into `folder`, which must exist and be empty.
    /// `progress` receives the fraction of bytes done, from 0 to 1.
    func download(
        repoId: String, into folder: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard ModelStorage.isValidRepoId(repoId) else { throw HubDownloadError.invalidRepoId(repoId) }
        let files = Self.neededFiles(try await listFiles(repoId: repoId))
        guard files.contains(where: { $0.path == "config.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") })
        else { throw HubDownloadError.notAModel }

        let total = max(1, files.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        progress(0)
        for file in files {
            try Task.checkCancellation()
            let finished = done
            let delegate = ProgressDelegate { written in
                progress(min(1, Double(finished + written) / Double(total)))
            }
            let url = Self.base.appendingPathComponent(repoId)
                .appendingPathComponent("resolve/main")
                .appendingPathComponent(file.path)
            let (temp, response) = try await session.download(from: url, delegate: delegate)
            defer { try? FileManager.default.removeItem(at: temp) }
            try Self.check(response)
            try FileManager.default.moveItem(at: temp, to: folder.appendingPathComponent(file.path))
            done += file.size
            progress(min(1, Double(done) / Double(total)))
        }
    }

    private func listFiles(repoId: String) async throws -> [RepoFile] {
        let url = Self.base.appendingPathComponent("api/models")
            .appendingPathComponent(repoId)
            .appendingPathComponent("tree/main")
        let (data, response) = try await session.data(from: url)
        try Self.check(response)
        return try JSONDecoder().decode([RepoFile].self, from: data)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw HubDownloadError.http(http.statusCode) }
    }
}

/// Forwards bytes received for one file download.
///
/// The async `download(from:delegate:)` doesn't call `didWriteData`, so the task's byte count is observed instead.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onWrite: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?

    init(onWrite: @escaping @Sendable (Int64) -> Void) {
        self.onWrite = onWrite
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let onWrite = onWrite
        let observation = task.observe(\.countOfBytesReceived) { task, _ in
            onWrite(task.countOfBytesReceived)
        }
        lock.withLock { self.observation = observation }
    }

    deinit {
        observation?.invalidate()
    }
}
