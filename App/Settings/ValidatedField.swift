import SwiftUI

/// A text field that saves each valid edit and shows why an invalid one wasn't saved.
/// While the text is invalid, the last valid value stays saved.
struct ValidatedField: View {
    let title: String
    let saved: String
    var prompt: String?
    let validate: (String) -> String?
    let commit: (String) -> Void

    @State private var draft: String
    @State private var error: String?

    init(
        _ title: String, saved: String, prompt: String? = nil,
        validate: @escaping (String) -> String?, commit: @escaping (String) -> Void
    ) {
        self.title = title
        self.saved = saved
        self.prompt = prompt
        self.validate = validate
        self.commit = commit
        _draft = State(initialValue: saved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $draft, prompt: prompt.map { Text($0) })
                .onChange(of: draft) { _, new in
                    error = validate(new)
                    if error == nil, new != saved { commit(new) }
                }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
