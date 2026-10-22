import SwiftUI
import TimesheetCore

/// The working day, lunch break and rounding step used when scheduling and checking lines.
struct WorkingHoursTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    @State private var start = ""
    @State private var end = ""
    @State private var lunchStart = ""
    @State private var lunchEnd = ""
    @State private var loaded = false

    private var saved: WorkingHours { store.settings.workingHours }

    var body: some View {
        let parsed = parse()
        Form {
            Section("Day") {
                timeField("Start", text: $start, result: parsed.start)
                timeField("End", text: $end, result: parsed.end)
            }
            Section {
                timeField("Lunch start", text: $lunchStart, result: parsed.lunchStart)
                timeField("Lunch end", text: $lunchEnd, result: parsed.lunchEnd)
            } header: {
                Text("Lunch")
            } footer: {
                Text("Set both to the same time for no lunch break.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = parsed.rangeError {
                Text(error).foregroundStyle(.red)
            }
            Section("Rounding") {
                Picker("Round times to", selection: roundingBinding) {
                    ForEach(SettingsValidation.roundingOptions, id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
            Section {
                LabeledContent("Working time", value: Self.duration(LineValidator.workingMinutes(saved)))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            start = saved.start.hhmm
            end = saved.end.hhmm
            lunchStart = saved.lunchStart.hhmm
            lunchEnd = saved.lunchEnd.hhmm
        }
        .onChange(of: [start, end, lunchStart, lunchEnd]) {
            guard loaded, let hours = parse().valid, hours != saved else { return }
            session.update { $0.workingHours = hours }
        }
    }

    private struct Parsed {
        var start, end, lunchStart, lunchEnd: Result<ClockTime, ValidationMessage>
        var rangeError: String?
        var valid: WorkingHours?
    }

    private func parse() -> Parsed {
        var p = Parsed(
            start: SettingsValidation.clockTime(start), end: SettingsValidation.clockTime(end),
            lunchStart: SettingsValidation.clockTime(lunchStart), lunchEnd: SettingsValidation.clockTime(lunchEnd))
        guard case .success(let s) = p.start, case .success(let e) = p.end,
              case .success(let ls) = p.lunchStart, case .success(let le) = p.lunchEnd
        else { return p }
        let hours = WorkingHours(start: s, end: e, lunchStart: ls, lunchEnd: le, roundingMinutes: saved.roundingMinutes)
        p.rangeError = SettingsValidation.workingHoursError(hours)
        p.valid = p.rangeError == nil ? hours : nil
        return p
    }

    private func timeField(_ title: String, text: Binding<String>, result: Result<ClockTime, ValidationMessage>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text, prompt: Text("HH:mm"))
            if case .failure(let m) = result, loaded {
                Text(m.text)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var roundingBinding: Binding<Int> {
        Binding(
            get: { saved.roundingMinutes },
            set: { minutes in session.update { $0.workingHours.roundingMinutes = minutes } })
    }

    private static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
