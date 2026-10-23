import SwiftUI
import TimesheetCore

/// Lets the user replace the built-in compile instructions sent to the model.
struct DeveloperTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    @State private var text = ""
    @State private var loaded = false

    private var saved: String? { store.settings.systemPromptOverride }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 380)
                    .labelsHidden()
            } header: {
                HStack {
                    Text("System prompt")
                    Spacer()
                    Button("Reset to default") {
                        session.update { $0.systemPromptOverride = nil }
                        text = PromptBuilder.system
                    }
                    .disabled(saved == nil && text == PromptBuilder.system)
                }
            } footer: {
                Text("Replaces the built-in instructions sent with every compile. Entries, lists and the reply schema are still added automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollsOnlyWhenOverflowing()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = saved ?? PromptBuilder.system
        }
        .onChange(of: text) {
            guard loaded else { return }
            let override = Self.override(for: text)
            guard override != saved else { return }
            session.update { $0.systemPromptOverride = override }
        }
    }

    /// Blank text or the built-in prompt means no override, so later built-in changes still apply.
    private static func override(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let builtIn = PromptBuilder.system.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == builtIn ? nil : text
    }
}
