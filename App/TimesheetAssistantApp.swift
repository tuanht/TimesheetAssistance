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
        }
        .commands {
            // ⌘N belongs to "New Entry" in the daily log, not to a second window.
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(settings.store)
                .environmentObject(settings)
                .environmentObject(models)
        }
    }

    private static func modelsDirectory() -> URL {
        if let directory = try? AppPaths.modelsDirectory() { return directory }
        // Application Support couldn't be resolved; downloads then last only until the temporary folder is cleared.
        return FileManager.default.temporaryDirectory.appendingPathComponent("TimesheetAssistance-Models", isDirectory: true)
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
