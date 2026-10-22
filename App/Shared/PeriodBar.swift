import SwiftUI
import TimesheetCore

/// Period picker shared by the daily log and Compile: step back or forward, pick a date, jump to today, choose the period kind.
struct PeriodBar: View {
    @Binding var anchor: Date
    @Binding var kind: PeriodKind
    /// Compile hides it and shows its own Day|Week|Month|Custom picker instead.
    let showsKindPicker: Bool

    init(anchor: Binding<Date>, kind: Binding<PeriodKind>, showsKindPicker: Bool = true) {
        _anchor = anchor
        _kind = kind
        self.showsKindPicker = showsKindPicker
    }

    var body: some View {
        HStack {
            Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous \(unit)")
                .help("Previous \(unit)")
            CalendarButton(title: Period.label(kind, anchor: anchor), date: $anchor,
                           accessibilityLabel: kind.displayName)
            Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next \(unit)")
                .help("Next \(unit)")
            Button("Today") { anchor = Date() }
                .disabled(containsToday)
            Spacer()
            if showsKindPicker {
                Picker("Period", selection: $kind) {
                    ForEach(PeriodKind.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var unit: String { kind.displayName.lowercased() }

    private var containsToday: Bool {
        Period.range(kind, containing: anchor).keys().contains(DayKey.string(for: Date()))
    }

    private func shift(by steps: Int) {
        anchor = Period.shift(anchor, by: steps, kind: kind)
    }
}
