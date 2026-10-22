import SwiftData
import SwiftUI
import TimesheetCore

@main
struct TimesheetAssistantApp: App {
    private let storeLoad: StoreLoad = StoreLoad.open()

    var body: some Scene {
        WindowGroup {
            switch storeLoad {
            case .ready(let container):
                RootView().modelContainer(container)
            case .failed(let message, let path):
                StoreErrorView(message: message, path: path)
            }
        }
        .commands {
            // ⌘N belongs to "New Entry" in the daily log, not to a second window.
            CommandGroup(replacing: .newItem) {}
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
