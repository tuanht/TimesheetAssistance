import SwiftUI

/// Shown in place of the app when the data store cannot be opened.
struct StoreErrorView: View {
    let message: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The data store could not be opened", systemImage: "exclamationmark.triangle")
                .font(.title2)
            Text(message)
                .textSelection(.enabled)
            Text("Store path")
                .font(.headline)
            Text(path)
                .font(.body.monospaced())
                .textSelection(.enabled)
            Text("Your data has not been changed. Quit the app, check the file above, then reopen.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 240, alignment: .topLeading)
    }
}
