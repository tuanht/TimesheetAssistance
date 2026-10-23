import SwiftUI
import TimesheetCore

/// The Settings window. The selected tab is shared through `settingsTab` so other screens can open a specific tab.
struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "template"
    @EnvironmentObject private var session: SettingsSession

    var body: some View {
        TabView(selection: $tab) {
            TemplateTab()
                .tabItem { Label("Template", systemImage: "text.alignleft") }
                .tag("template")
            ListsTab()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
                .tag("lists")
            WorkingHoursTab()
                .tabItem { Label("Working hours", systemImage: "clock") }
                .tag("workingHours")
            ModelsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag("models")
            IntegrationsTab()
                .tabItem { Label("Integrations", systemImage: "link") }
                .tag("integrations")
            DeveloperTab()
                .tabItem { Label("Developer", systemImage: "hammer") }
                .tag("developer")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if !session.isPersistent {
                    Label("The settings file location couldn’t be resolved. Changes won’t be saved.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if let saveError = session.saveError {
                    Label(saveError, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, session.isPersistent && session.saveError == nil ? 0 : 8)
        }
        .frame(width: 560, height: 600)
        .background(OpensBesideMainWindow())
    }
}
