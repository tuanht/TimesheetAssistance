import Testing
@testable import TimesheetCore

@Suite struct AppPathsTests {
    @Test func rootEndsWithAppFolder() throws {
        #expect(try AppPaths.root().path.hasSuffix("Application Support/TimesheetAssistance"))
        #expect(try AppPaths.settingsFile().lastPathComponent == "settings.json")
        #expect(try AppPaths.storeFile().lastPathComponent == "store.sqlite")
        #expect(try AppPaths.modelsDirectory().lastPathComponent == "Models")
    }
}
