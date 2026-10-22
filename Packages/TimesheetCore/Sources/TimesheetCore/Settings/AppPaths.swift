import Foundation

public enum AppPaths {
    /// `~/Library/Application Support/TimesheetAssistance/`, created if missing.
    public static func root(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("TimesheetAssistance", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public static func settingsFile() throws -> URL {
        try root().appendingPathComponent("settings.json", isDirectory: false)
    }

    public static func storeFile() throws -> URL {
        try root().appendingPathComponent("store.sqlite", isDirectory: false)
    }

    public static func modelsDirectory() throws -> URL {
        try root().appendingPathComponent("Models", isDirectory: true)
    }
}
