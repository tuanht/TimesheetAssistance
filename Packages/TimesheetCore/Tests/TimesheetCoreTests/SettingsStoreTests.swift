import Foundation
import Testing
@testable import TimesheetCore

struct SettingsStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    @Test func roundTrip() throws {
        let url = tempURL()
        let store = SettingsStore(url: url)
        store.settings.activityTypes = ["Alpha"]
        store.settings.workingHours.roundingMinutes = 5
        store.settings.model = .endpoint(EndpointConfig(
            baseURL: URL(string: "https://example.com/v1")!, model: "m", remoteConfirmed: true))
        try store.save()
        let reloaded = SettingsStore(url: url)
        #expect(reloaded.settings == store.settings)
    }

    @Test func missingFileGivesDefault() {
        #expect(SettingsStore(url: tempURL()).settings == .default)
    }

    @Test func corruptFileGivesDefaultAndBackup() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{".write(to: url, atomically: true, encoding: .utf8)
        let store = SettingsStore(url: url)
        #expect(store.settings == .default)
        let bak = url.deletingLastPathComponent().appendingPathComponent("settings.json.bak")
        #expect(FileManager.default.fileExists(atPath: bak.path))
    }
}
