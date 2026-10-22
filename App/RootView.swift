import Combine
import SwiftUI
import TimesheetCore

struct RootView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case dailyLog = "Daily log"
        case compile = "Compile"
        var id: String { rawValue }
    }

    @State private var selection: Section? = .dailyLog
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
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .dailyLog:
                DailyLogView(anchor: $anchor, kind: $logPeriod)
            case .compile:
                CompileView(anchor: $anchor, kind: $compileRange, customStart: $customStart, customEnd: $customEnd)
            case nil:
                EmptyView()
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
