import Foundation
import Combine

public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings
    private let url: URL

    public init(url: URL) {
        self.url = url
        self.settings = Self.load(from: url)
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> AppSettings {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .default }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        } catch {
            let bak = url.appendingPathExtension("bak")
            try? fm.removeItem(at: bak)
            try? fm.moveItem(at: url, to: bak)
            return .default
        }
    }
}
