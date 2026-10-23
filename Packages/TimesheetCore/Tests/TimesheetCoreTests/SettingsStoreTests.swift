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

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func date(_ text: String) throws -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return try #require(f.date(from: text))
    }

    private func backups(beside url: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasSuffix(".bak") }.sorted()
    }

    @Test func fileMissingNewerFieldsKeepsPresentValuesAndDefaultsTheRest() throws {
        let url = tempURL()
        try write("""
            {
              "activityTypes": ["Alpha"],
              "template": { "separator": ",", "maxDescriptionLength": 80 },
              "workingHours": { "start": "08:00" },
              "model": { "local": { "repoId": "mlx-community/Qwen3-4B-4bit" } }
            }
            """, to: url)
        let store = SettingsStore(url: url)
        var expected = AppSettings.default
        expected.activityTypes = ["Alpha"]
        expected.template.separator = ","
        expected.template.maxDescriptionLength = 80
        expected.workingHours.start = ClockTime(8, 0)
        expected.model = .local(repoId: "mlx-community/Qwen3-4B-4bit")
        #expect(store.settings == expected)
        #expect(store.resetBackupURL == nil)
        #expect(backups(beside: url).isEmpty)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let url = tempURL()
        try write("{}", to: url)
        #expect(SettingsStore(url: url).settings == .default)
    }

    @Test func endpointMissingNewerFieldsKeepsIt() throws {
        let url = tempURL()
        try write("""
            { "model": { "endpoint": { "_0": { "baseURL": "http://localhost:11434", "model": "m" } } } }
            """, to: url)
        let expected = EndpointConfig(baseURL: URL(string: "http://localhost:11434")!, model: "m", remoteConfirmed: false)
        #expect(SettingsStore(url: url).settings.model == .endpoint(expected))
    }

    @Test func unknownModelSelectionBecomesNoneAndKeepsTheRest() throws {
        let url = tempURL()
        try write(#"{ "activityTypes": ["Alpha"], "model": { "cloud": { "id": 1 } } }"#, to: url)
        let store = SettingsStore(url: url)
        #expect(store.settings.model == ModelSelection.none)
        #expect(store.settings.activityTypes == ["Alpha"])
        #expect(store.resetBackupURL == nil)
    }

    @Test func corruptFileGivesDefaultAndTimestampedBackup() throws {
        let url = tempURL()
        try write("{", to: url)
        let store = SettingsStore(url: url, now: { try! date("2026-10-22 09:05:07") })
        #expect(store.settings == .default)
        let bak = url.deletingLastPathComponent().appendingPathComponent("settings.json.20261022-090507.bak")
        #expect(store.resetBackupURL == bak)
        #expect(FileManager.default.fileExists(atPath: bak.path))
        #expect(try String(contentsOf: bak, encoding: .utf8) == "{")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func secondResetKeepsTheFirstBackup() throws {
        let url = tempURL()
        try write("{", to: url)
        _ = SettingsStore(url: url, now: { try! date("2026-10-22 09:00:00") })
        try write("[", to: url)
        let second = SettingsStore(url: url, now: { try! date("2026-10-23 10:00:00") })
        #expect(backups(beside: url) == ["settings.json.20261022-090000.bak", "settings.json.20261023-100000.bak"])
        #expect(second.resetBackupURL?.lastPathComponent == "settings.json.20261023-100000.bak")
    }

    @Test func resetsInTheSameSecondKeepBothBackups() throws {
        let url = tempURL()
        try write("{", to: url)
        _ = SettingsStore(url: url, now: { try! date("2026-10-22 09:00:00") })
        try write("[", to: url)
        let second = SettingsStore(url: url, now: { try! date("2026-10-22 09:00:00") })
        #expect(backups(beside: url).count == 2)
        let bak = try #require(second.resetBackupURL)
        #expect(try String(contentsOf: bak, encoding: .utf8) == "[")
    }

    // MARK: Integrations

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func decodesWithoutIntegrations() throws {
        let settings = try decode(#"{ "activityTypes": ["Alpha"] }"#)
        #expect(settings.integrations == .default)
        #expect(settings.activityTypes == ["Alpha"])
    }

    @Test func decodesPartialIntegrations() throws {
        let settings = try decode(#"{ "integrations": { "defaultRepo": "acme/web" } }"#)
        var expected = IntegrationSettings.default
        expected.defaultRepo = "acme/web"
        #expect(settings.integrations == expected)
    }

    @Test func unknownAuthMethodFallsBack() throws {
        let settings = try decode(#"{ "integrations": { "jiraMethod": "smokeSignal", "githubMethod": "appSignIn" } }"#)
        #expect(settings.integrations.jiraMethod == .personalToken)
        #expect(settings.integrations.githubMethod == .appSignIn)
    }

    @Test func roundTripsIntegrations() throws {
        let url = tempURL()
        let store = SettingsStore(url: url)
        store.settings.integrations = IntegrationSettings(
            jiraMethod: .appSignIn, jiraSiteId: "site-1", jiraEmail: "dev@example.com",
            githubMethod: .appSignIn, githubAppClientId: "client-1", defaultRepo: "acme/web")
        try store.save()
        #expect(SettingsStore(url: url).settings == store.settings)
    }

    @Test func integrationDefaults() {
        let d = IntegrationSettings.default
        #expect(d.jiraMethod == .personalToken)
        #expect(d.githubMethod == .personalToken)
        #expect(d.jiraSiteId == nil && d.jiraEmail == nil && d.githubAppClientId == nil && d.defaultRepo == nil)
        #expect(AppSettings.default.integrations == .default)
        #expect(AuthMethod.personalToken.displayName == "Personal token")
        #expect(AuthMethod.appSignIn.displayName == "App sign-in")
    }
}
