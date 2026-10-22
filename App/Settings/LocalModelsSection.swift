import LocalModels
import SwiftUI
import TimesheetCore

/// The catalog models that fit this Mac: download, cancel, delete, and choose the one to use.
struct LocalModelsSection: View {
    let tier: RAMTier

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession
    @EnvironmentObject private var models: MLXModelManager

    /// Last download failure per model id, shown under its row until the next attempt.
    @State private var errors: [String: String] = [:]
    @State private var pendingDelete: CatalogModel?

    private var selectedId: String? {
        if case .local(let repoId) = store.settings.model { return repoId }
        return nil
    }

    var body: some View {
        Section {
            ForEach(ModelCatalog.available(for: tier)) { item in
                row(item)
            }
        } header: {
            Text("Models for this Mac")
        } footer: {
            Text("Models download from Hugging Face and stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert(
            "Delete \(pendingDelete?.displayName ?? "model")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text("This frees about \(Self.sizeText(item.approxGB)). You can download it again later.")
        }
    }

    @ViewBuilder
    private func row(_ item: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    Text(Self.sizeText(item.approxGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                controls(item)
            }
            if case .endpointOnly(let reason) = item.runtime {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fraction = models.progress[item.id] {
                ProgressView(value: fraction)
            }
            if let error = errors[item.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func controls(_ item: CatalogModel) -> some View {
        if case .endpointOnly = item.runtime {
            Text("Endpoint only")
                .foregroundStyle(.secondary)
        } else if models.progress[item.id] != nil {
            Button("Cancel") { models.cancel(item.id) }
        } else if models.isDownloaded(item.id) {
            if selectedId == item.id {
                Label("In use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Use") { session.update { $0.model = .local(repoId: item.id) } }
            }
            Button("Delete…", role: .destructive) { pendingDelete = item }
        } else {
            Button("Download") { download(item) }
        }
    }

    private func download(_ item: CatalogModel) {
        errors[item.id] = nil
        Task {
            do {
                try await models.download(item.id)
            } catch is CancellationError {
                // The user cancelled; nothing to report.
            } catch {
                errors[item.id] = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func delete(_ item: CatalogModel) {
        pendingDelete = nil
        do {
            try models.delete(item.id)
            errors[item.id] = nil
            if selectedId == item.id {
                session.update { $0.model = .none }
            }
        } catch {
            errors[item.id] = "Couldn’t delete the model: \(error.localizedDescription)"
        }
    }

    private static func sizeText(_ gb: Double) -> String {
        "\(gb.formatted(.number.precision(.fractionLength(0...1)))) GB"
    }
}
