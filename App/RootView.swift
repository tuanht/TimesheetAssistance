import Combine
import SwiftUI
import TimesheetCore

struct RootView: View {
    private enum Section: String, CaseIterable, Identifiable {
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
        // The centered tabs already name the page; the title stays set for the Window menu and Mission Control.
        .toolbar(removing: .title)
        .background { tabShortcuts }
        // Tall enough for the entry editor sheet at its minimum height.
        .frame(minWidth: 720, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            followToday()
        }
        .onChange(of: scenePhase) { if scenePhase == .active { followToday() } }
    }

    /// ⌘1/⌘2 live in this window, not the menu bar: AppKit routes key equivalents to the key window, so
    /// while a sheet, dialog or alert is up they never reach here and can't tear down a draft.
    private var tabShortcuts: some View {
        ZStack {
            Button("Log") { selection = .log }
                .keyboardShortcut("1", modifiers: .command)
            Button("Compile") { selection = .compile }
                .keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
