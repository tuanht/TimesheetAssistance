import Foundation
import SwiftData

/// CloudKit is disabled explicitly in every configuration: user data must never leave the Mac,
/// and the default `.automatic` would start syncing as soon as the app gained iCloud entitlements.
public enum Store {
    /// On-disk store at `url`; the app passes `AppPaths.storeFile()`.
    public static func container(url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: url, cloudKitDatabase: .none))
    }

    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// Entries for the calendar date of `day` in `timeZone`, oldest first.
    public static func entries(on day: Date, in context: ModelContext, timeZone: TimeZone = .current) throws -> [LogEntry] {
        let key = DayKey.string(for: day, timeZone: timeZone)
        return try context.fetch(FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.createdAt)]))
    }

    public static func compiled(on day: Date, in context: ModelContext, timeZone: TimeZone = .current) throws -> CompiledDay? {
        let key = DayKey.string(for: day, timeZone: timeZone)
        var descriptor = FetchDescriptor<CompiledDay>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static let schema = Schema([LogEntry.self, CompiledDay.self])
}
