import Foundation

/// Where a model's files live on disk, and when a folder counts as a complete download.
///
/// Each model gets `<models directory>/<org>--<name>/`. Downloads are staged under
/// `<models directory>/.downloads/` and moved into place only once every file has arrived.
enum ModelStorage {
    static let stagingFolderName = ".downloads"

    /// Hugging Face repo ids look like `org/name`; anything else is refused so it can't escape the directory.
    static func isValidRepoId(_ id: String) -> Bool {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty && !part.hasPrefix(".")
                && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    static func folderName(for id: String) -> String {
        id.replacingOccurrences(of: "/", with: "--")
    }

    static func folder(for id: String, in directory: URL) -> URL {
        directory.appendingPathComponent(folderName(for: id), isDirectory: true)
    }

    static func stagingFolder(for id: String, in directory: URL) -> URL {
        directory.appendingPathComponent(stagingFolderName, isDirectory: true)
            .appendingPathComponent(folderName(for: id), isDirectory: true)
    }

    /// A folder holds a usable model when it has `config.json` and at least one `*.safetensors` file.
    static func isComplete(_ folder: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: folder.appendingPathComponent("config.json").path),
              let names = try? fileManager.contentsOfDirectory(atPath: folder.path)
        else { return false }
        return names.contains { $0.hasSuffix(".safetensors") }
    }
}
