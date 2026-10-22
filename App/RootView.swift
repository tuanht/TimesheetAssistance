import SwiftUI

struct RootView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case dailyLog = "Daily log"
        case compile = "Compile"
        var id: String { rawValue }
    }

    @State private var selection: Section? = .dailyLog
    /// Shared by the daily log and Compile so both work on the same day.
    @State private var day = Date()

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .dailyLog:
                DailyLogView(day: $day)
            case .compile, nil:
                Text(selection?.rawValue ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 440)
    }
}
