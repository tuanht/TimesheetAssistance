import SwiftUI

/// A button showing `title` that opens a month-grid date picker; picking a date sets `date` and closes it.
struct CalendarButton: View {
    let title: String
    @Binding var date: Date
    let accessibilityLabel: String

    @State private var isPresented = false

    init(title: String, date: Binding<Date>, accessibilityLabel: String) {
        self.title = title
        _date = date
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Button { isPresented = true } label: {
            Label(title, systemImage: "calendar")
                .monospacedDigit()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title)
        .help("Pick a date")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DatePicker(accessibilityLabel, selection: pick, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
        }
    }

    /// Writes the picked date through and closes the popover.
    private var pick: Binding<Date> {
        Binding(get: { date }, set: { date = $0; isPresented = false })
    }
}
