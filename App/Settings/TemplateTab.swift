import SwiftUI
import TimesheetCore

/// Output line template: a live sample, field order and visibility, separators, formats and ticket pattern.
struct TemplateTab: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    private var template: TemplateSettings { store.settings.template }

    var body: some View {
        Form {
            // The live sample sits right above the chips that shape it.
            Section("Line") {
                Text(LineRenderer.render([Self.sampleLine], day: Date(), template: template))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FieldChipsEditor(saved: template.fields) { fields in
                    session.update { $0.template.fields = fields }
                }
            }
            Section("Text") {
                ValidatedField("Separator", saved: template.separator,
                               validate: { v in
                                   // The pair must stay valid whichever side changes.
                                   SettingsValidation.separatorError(v)
                                       ?? SettingsValidation.separatorSubstituteError(
                                           template.separatorSubstitute, separator: v)
                                       .map { _ in "The separator substitute contains this separator." }
                               }) { v in
                    session.update { $0.template.separator = v }
                }
                ValidatedField("Separator substitute", saved: template.separatorSubstitute,
                               validate: { v in
                                   SettingsValidation.separatorSubstituteError(v, separator: template.separator)
                               }) { v in
                    session.update { $0.template.separatorSubstitute = v }
                }
                ValidatedField("Empty ticket placeholder", saved: template.emptyTicketPlaceholder,
                               validate: { _ in nil }) { v in
                    session.update { $0.template.emptyTicketPlaceholder = v }
                }
                ValidatedField("Date format", saved: template.dateFormat, prompt: "yyyy-MM-dd",
                               validate: SettingsValidation.formatError) { v in
                    session.update { $0.template.dateFormat = v }
                }
                ValidatedField("Time format", saved: template.timeFormat, prompt: "HH:mm",
                               validate: SettingsValidation.formatError) { v in
                    session.update { $0.template.timeFormat = v }
                }
                ValidatedField("Ticket pattern", saved: template.ticketPattern,
                               validate: SettingsValidation.ticketPatternError) { v in
                    session.update { $0.template.ticketPattern = v }
                }
                Toggle("Limit description length", isOn: limitBinding)
                if let max = template.maxDescriptionLength {
                    ValidatedField("Maximum characters", saved: String(max),
                                   validate: { text in
                                       if case .failure(let m) = SettingsValidation.maxDescriptionLength(text) { m.text } else { nil }
                                   }) { text in
                        if case .success(let n) = SettingsValidation.maxDescriptionLength(text) {
                            session.update { $0.template.maxDescriptionLength = n }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollsOnlyWhenOverflowing()
    }

    private var limitBinding: Binding<Bool> {
        Binding(
            get: { template.maxDescriptionLength != nil },
            set: { on in session.update { $0.template.maxDescriptionLength = on ? Self.defaultMaxLength : nil } })
    }

    private static let defaultMaxLength = 80

    /// Fixed content so only the template changes what the sample shows.
    static let sampleLine = TimesheetLine(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        entryId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        start: ClockTime(9, 0), end: ClockTime(10, 30),
        description: "Fix login redirect | add regression test",
        ticket: "PROJ-123", activityType: "Development", classification: "Billable")
}
