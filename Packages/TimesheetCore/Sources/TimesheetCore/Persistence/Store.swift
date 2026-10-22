import Foundation
import SwiftData

public enum Store {
    /// On-disk store at `url`; the app passes `AppPaths.storeFile()`.
    public static func container(url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
    }

    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    /// Entries for the calendar day containing `day`, oldest first.
    public static func entries(on day: Date, in context: ModelContext) throws -> [LogEntry] {
        let start = Calendar.current.startOfDay(for: day)
        return try context.fetch(FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.day == start },
            sortBy: [SortDescriptor(\.createdAt)]))
    }

    public static func compiled(on day: Date, in context: ModelContext) throws -> CompiledDay? {
        let start = Calendar.current.startOfDay(for: day)
        var descriptor = FetchDescriptor<CompiledDay>(predicate: #Predicate { $0.day == start })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static let schema = Schema([LogEntry.self, CompiledDay.self])
}
