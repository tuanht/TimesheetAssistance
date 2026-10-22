import Combine
import SwiftUI
import TimesheetCore

struct RootView: View {
    /// The window's tabs. Also read by the ⌘1/⌘2 menu commands through the same "mainTab" key.
    enum Section: String, CaseIterable, Identifiable {
        case log = "Log"
        case compile = "Compile"
        var id: String { rawValue }
    }

    @AppStorage("mainTab") private var selection: Section = .log
    /// Shared by the daily log and Compile so both work on the same day.
    @State private var anchor = Date()
    /// Which period the daily log shows around `anchor`.
    @AppStorage("logPeriod") private var logPeriod: PeriodKind = .day
    /// What Compile works on: a period around `anchor`, or the custom range below.
    @AppStorage("compileRange") private var compileRange: CompileRangeKind = .day
    @State private var customStart = Date()
    @State private var customEnd = Date()
    /// The calendar date that was "today" when last checked, so a day change can move `anchor` along.
    @State private var today = DayKey.string(for: Date())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch selection {
            case .log:
                DailyLogView(anchor: $anchor, kind: $logPeriod)
            case .compile:
                CompileView(anchor: $anchor, kind: $compileRange, customStart: $customStart, customEnd: $customEnd)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $selection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            followToday()
        }
        .onChange(of: scenePhase) { if scenePhase == .active { followToday() } }
    }

    /// After midnight, a window left on the old today moves to the new one; a day the user picked stays.
    private func followToday() {
        let now = Date()
        let newToday = DayKey.string(for: now)
        guard newToday != today else { return }
        if DayKey.string(for: anchor) == today { anchor = now }
        today = newToday
    }
}
