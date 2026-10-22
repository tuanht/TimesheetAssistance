import SwiftUI
import TimesheetCore

/// Connects Jira and GitHub for ticket and PR context, and sets the repo for bare "#45" references.
struct IntegrationsTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    var body: some View {
        Form {
            IntegrationServiceSection(service: .jira)
            IntegrationServiceSection(service: .github)
            Section {
                ValidatedField(
                    "Default repo", saved: store.settings.integrations.defaultRepo ?? "", prompt: "owner/repo",
                    validate: { SettingsValidation.defaultRepoError(Self.trimmed($0)) },
                    commit: { value in
                        let repo = Self.trimmed(value)
                        session.update { $0.integrations.defaultRepo = repo.isEmpty ? nil : repo }
                    })
            } header: {
                Text("Pull requests")
            } footer: {
                Text("Used for references written as #45.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
