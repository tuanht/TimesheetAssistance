import Foundation
import Combine

public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings
    /// Set when the settings file couldn't be read and was moved here before resetting to defaults,
    /// so the app can tell the user once.
    public let resetBackupURL: URL?
    private let url: URL

    public init(url: URL, now: () -> Date = Date.init) {
        self.url = url
        let loaded = Self.load(from: url, now: now)
        self.settings = loaded.settings
        self.resetBackupURL = loaded.backup
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }

    private static func load(from url: URL, now: () -> Date) -> (settings: AppSettings, backup: URL?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return (.default, nil) }
        do {
            return (try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url)), nil)
        } catch {
            let bak = backupURL(for: url, at: now())
            guard (try? fm.moveItem(at: url, to: bak)) != nil else { return (.default, nil) }
            return (.default, bak)
        }
    }

    /// `settings.json.<yyyyMMdd-HHmmss>.bak`, with a counter if that name is taken, so no earlier backup is overwritten.
    private static func backupURL(for url: URL, at date: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: date)
        let folder = url.deletingLastPathComponent()
        var candidate = folder.appendingPathComponent("\(url.lastPathComponent).\(stamp).bak")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(url.lastPathComponent).\(stamp)-\(counter).bak")
            counter += 1
        }
        return candidate
    }
}
