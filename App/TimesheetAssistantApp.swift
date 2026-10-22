import Combine
import LocalModels
import SwiftData
import SwiftUI
import TimesheetCore

@main
struct TimesheetAssistantApp: App {
    private let storeLoad: StoreLoad = StoreLoad.open()
    /// One settings store for every window, so edits in Settings show up live elsewhere.
    @StateObject private var settings = SettingsSession.open()
    /// One model manager, so a download keeps running when the Settings window closes.
    @StateObject private var models = MLXModelManager(directory: Self.modelsDirectory())
    /// The main window's tab, for the ⌘1/⌘2 menu commands.
    @AppStorage("mainTab") private var mainTab: RootView.Section = .log

    var body: some Scene {
        WindowGroup {
            Group {
                switch storeLoad {
                case .ready(let container):
                    RootView().modelContainer(container)
                case .failed(let message, let path):
                    StoreErrorView(message: message, path: path)
                }
            }
            .environmentObject(settings.store)
            .environmentObject(settings)
            .environmentObject(models)
            .modifier(ReleasesUnusedModels(store: settings.store, models: models))
            .alert(
                "Settings were reset",
                isPresented: Binding(
                    get: { settings.resetNotice != nil },
                    set: { if !$0 { settings.resetNotice = nil } })
            ) {
                Button("OK") { settings.resetNotice = nil }
            } message: {
                Text(settings.resetNotice ?? "")
            }
        }
        .commands {
            // ⌘N belongs to "New Entry" in the daily log, not to a second window.
            CommandGroup(replacing: .newItem) {}
            // Writes the same key RootView reads, so the shortcuts work whichever tab is showing.
            CommandGroup(before: .sidebar) {
                Button("Log") { mainTab = .log }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Compile") { mainTab = .compile }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings.store)
                .environmentObject(settings)
                .environmentObject(models)
                .modifier(ReleasesUnusedModels(store: settings.store, models: models))
        }
    }

    private static func modelsDirectory() -> URL {
        if let directory = try? AppPaths.modelsDirectory() { return directory }
        // Application Support couldn't be resolved; downloads then last only until the temporary folder is cleared.
        return FileManager.default.temporaryDirectory.appendingPathComponent("TimesheetAssistance-Models", isDirectory: true)
    }
}

/// Frees on-device models from memory once compiling no longer runs on this Mac. On both scenes, so it
/// works whichever window is open when the selection changes.
private struct ReleasesUnusedModels: ViewModifier {
    let store: SettingsStore
    let models: MLXModelManager

    func body(content: Content) -> some View {
        content.onReceive(store.$settings.map(\.model).removeDuplicates()) { selection in
            if case .local = selection { return }
            models.releaseClients()
        }
    }
}

/// Outcome of opening the on-disk store; a failure is shown to the user instead of crashing.
enum StoreLoad {
    case ready(ModelContainer)
    case failed(message: String, path: String)

    static func open() -> StoreLoad {
        let url: URL
        do {
            url = try AppPaths.storeFile()
        } catch {
            return .failed(message: error.localizedDescription, path: "(could not resolve the store path)")
        }
        do {
            return .ready(try Store.container(url: url))
        } catch {
            return .failed(message: String(describing: error), path: url.path)
        }
    }
}
