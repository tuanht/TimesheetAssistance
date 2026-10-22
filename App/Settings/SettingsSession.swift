import Foundation
import SwiftUI
import TimesheetCore

/// Owns the app's one `SettingsStore` and applies edits to it, saving each valid change.
@MainActor
final class SettingsSession: ObservableObject {
    let store: SettingsStore
    /// False when the settings file path could not be resolved; edits then live in memory only.
    let isPersistent: Bool
    @Published private(set) var saveError: String?
    /// Shown once in the main window when the settings file couldn't be read and was reset.
    @Published var resetNotice: String?

    init(store: SettingsStore, isPersistent: Bool) {
        self.store = store
        self.isPersistent = isPersistent
        if let backup = store.resetBackupURL {
            resetNotice = "Your settings couldn't be read and were reset. A backup was saved to \(backup.path)."
        }
    }

    static func open() -> SettingsSession {
        do {
            return SettingsSession(store: SettingsStore(url: try AppPaths.settingsFile()), isPersistent: true)
        } catch {
            // Never written: saving is skipped when not persistent, so this path only yields defaults.
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("TimesheetAssistance-\(UUID().uuidString).json")
            return SettingsSession(store: SettingsStore(url: scratch), isPersistent: false)
        }
    }

    /// Applies an already-validated edit and saves it.
    func update(_ edit: (inout AppSettings) -> Void) {
        edit(&store.settings)
        guard isPersistent else { return }
        do {
            try store.save()
            saveError = nil
        } catch {
            saveError = "Couldn’t save settings: \(error.localizedDescription)"
        }
    }
}
