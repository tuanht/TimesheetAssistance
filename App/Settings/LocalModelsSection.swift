import SwiftUI
import TimesheetCore

/// The catalog models that fit this Mac. Download controls arrive in Task 12.
struct LocalModelsSection: View {
    let tier: RAMTier

    var body: some View {
        Section {
            ForEach(ModelCatalog.available(for: tier)) { item in
                LabeledContent(item.displayName, value: Self.sizeText(item.approxGB))
            }
        } header: {
            Text("Models for this Mac")
        } footer: {
            Text("Downloading models to this Mac isn’t available yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func sizeText(_ gb: Double) -> String {
        "\(gb.formatted(.number.precision(.fractionLength(0...1)))) GB"
    }
}
