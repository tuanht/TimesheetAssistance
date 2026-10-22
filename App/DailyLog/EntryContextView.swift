import SwiftUI
import TimesheetCore

/// Under an entry row: its summary, then the context job's status with Retry, or Fetch details.
/// Status and buttons appear only when a service is connected; a saved summary always shows.
struct EntryContextView: View {
    let entry: LogEntry

    @EnvironmentObject private var coordinator: ContextCoordinator
    @State private var confirmingRetry = false

    var body: some View {
        if let summary {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        if coordinator.isAnyConnected {
            if let status = coordinator.status[entry.id] {
                statusLine(status)
            } else if summary == nil && !detected.references.isEmpty {
                Button("Fetch details") { coordinator.enqueue(entry) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ status: ContextStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if case .failed = status {
                Text(status.text).foregroundStyle(.red)
                Button("Retry", action: retry)
                    .controlSize(.small)
                    .confirmationDialog("Replace your edited summary?", isPresented: $confirmingRetry,
                                        titleVisibility: .visible) {
                        Button("Replace", role: .destructive) { coordinator.enqueue(entry) }
                        Button("Keep", role: .cancel) {}
                    }
            } else {
                Text(status.text).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    /// Retry asks first when a non-blank summary was edited after the failed job, like Refresh does.
    private func retry() {
        switch ContextPolicy.onRefresh(
            current: detected.canonical, hasSummary: summary != nil, edited: entry.contextEdited) {
        case .confirmReplace: confirmingRetry = true
        case .fetch: coordinator.enqueue(entry)
        case .none, .clear: break
        }
    }

    private var summary: String? {
        guard let text = entry.contextSummary,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private var detected: DetectedReferences { coordinator.detect(entry) }
}
