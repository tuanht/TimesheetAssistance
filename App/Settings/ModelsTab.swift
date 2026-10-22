import SwiftUI
import TimesheetCore

/// Chooses where compiling runs: a model on this Mac, or a custom OpenAI-compatible endpoint.
struct ModelsTab: View {
    private enum Source: Hashable {
        case local, endpoint
    }

    private enum TestState: Equatable {
        case idle
        case testing
        case success([String])
        case failure(String)
    }

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession

    @State private var source = Source.local
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var savedKey = ""
    @State private var loaded = false

    @State private var testState = TestState.idle
    @State private var testTask: Task<Void, Never>?
    /// Model ids from the last successful test, offered for the model name.
    @State private var offeredModels: [String] = []

    @State private var pendingRemote: EndpointConfig?
    @State private var keychainError: String?

    private let memory = ProcessInfo.processInfo.physicalMemory
    private var tier: RAMTier { RAMTier.forMemory(bytes: memory) }

    private var savedEndpoint: EndpointConfig? {
        if case .endpoint(let config) = store.settings.model { return config }
        return nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("This Mac", value: "\(Self.memoryText(memory)) · \(Self.tierText(tier))")
                Picker("Run models", selection: sourceBinding) {
                    Text("On this Mac").tag(Source.local)
                    Text("Custom endpoint").tag(Source.endpoint)
                }
                .pickerStyle(.segmented)
            }
            switch source {
            case .local: LocalModelsSection(tier: tier)
            case .endpoint: endpointSections
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onDisappear { cancelTest() }
        .onChange(of: [baseURL, apiKey]) {
            cancelTest()
            // The ids belong to the endpoint they came from.
            offeredModels = []
            keychainError = nil
        }
        .onChange(of: model) {
            // The test lists models without using the model name, so only an in-flight test is stale.
            if testState == .testing { cancelTest() }
            keychainError = nil
        }
        .alert(
            "Send entries to this endpoint?",
            isPresented: Binding(get: { pendingRemote != nil }, set: { if !$0 { pendingRemote = nil } }),
            presenting: pendingRemote
        ) { config in
            Button("Confirm") { apply(config) }
            Button("Cancel", role: .cancel) { pendingRemote = nil }
        } message: { _ in
            Text("This endpoint is not on this Mac or your local network. Your entries will be sent to it when you compile.")
        }
    }

    // MARK: Custom endpoint

    @ViewBuilder
    private var endpointSections: some View {
        let urlResult = SettingsValidation.endpointURL(baseURL)
        let modelError = SettingsValidation.endpointModelError(model)
        Section {
            fieldWithError(error: urlError(urlResult)) {
                TextField("Base URL", text: $baseURL, prompt: Text("http://localhost:11434"))
            }
            fieldWithError(error: model.isEmpty ? nil : modelError) {
                HStack {
                    TextField("Model name", text: $model)
                    if !offeredModels.isEmpty {
                        Menu("Models") {
                            ForEach(offeredModels, id: \.self) { id in
                                Button(id) { model = id }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
            SecureField("API key", text: $apiKey, prompt: Text("Optional"))
        } header: {
            Text("OpenAI-compatible endpoint")
        } footer: {
            Text("The API key is stored in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section {
            HStack {
                Button("Test connection") { test(urlResult) }
                    .disabled(!isValid(urlResult) || testState == .testing)
                if testState == .testing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Save") { save(urlResult) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid(urlResult) || modelError != nil || !isDirty(urlResult))
            }
            testResult
            if let keychainError {
                Text(keychainError).foregroundStyle(.red)
            }
            if savedEndpoint == nil {
                Text("Not in use until you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .success(let ids):
            VStack(alignment: .leading, spacing: 4) {
                Label("Connected.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(ids.isEmpty ? "The endpoint lists no models." : ids.joined(separator: "\n"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func fieldWithError(error: String?, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            field()
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Actions

    private var sourceBinding: Binding<Source> {
        Binding(
            get: { source },
            set: { new in
                source = new
                cancelTest()
                // Choosing "On this Mac" drops a saved endpoint; the form keeps its draft.
                if new == .local, savedEndpoint != nil {
                    session.update { $0.model = .none }
                }
            })
    }

    private func load() {
        guard !loaded else { return }
        if let config = savedEndpoint {
            source = .endpoint
            baseURL = config.baseURL.absoluteString
            model = config.model
        }
        savedKey = KeychainStore.get(account: KeychainStore.apiKeyAccount) ?? ""
        apiKey = savedKey
        loaded = true
    }

    private func isValid(_ result: Result<URL, ValidationMessage>) -> Bool {
        if case .success = result { return true }
        return false
    }

    /// Hidden while the field is empty; Save stays disabled instead.
    private func urlError(_ result: Result<URL, ValidationMessage>) -> String? {
        guard case .failure(let message) = result, !baseURL.isEmpty else { return nil }
        return message.text
    }

    private func isDirty(_ urlResult: Result<URL, ValidationMessage>) -> Bool {
        guard case .success(let url) = urlResult, let saved = savedEndpoint else { return true }
        return saved.baseURL != url || saved.model != trimmedModel || savedKey != apiKey
    }

    private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save(_ urlResult: Result<URL, ValidationMessage>) {
        guard case .success(let url) = urlResult, SettingsValidation.endpointModelError(model) == nil else { return }
        let config = EndpointConfig(baseURL: url, model: trimmedModel, remoteConfirmed: !EndpointPolicy.isLocal(url))
        if SettingsValidation.needsRemoteConfirmation(url, saved: store.settings.model) {
            pendingRemote = config
        } else {
            apply(config)
        }
    }

    private func apply(_ config: EndpointConfig) {
        pendingRemote = nil
        do {
            if apiKey.isEmpty {
                KeychainStore.delete(account: KeychainStore.apiKeyAccount)
            } else {
                try KeychainStore.set(apiKey, account: KeychainStore.apiKeyAccount)
            }
            savedKey = apiKey
        } catch {
            keychainError = "Couldn’t save the API key to the Keychain."
            return
        }
        session.update { $0.model = .endpoint(config) }
    }

    private func test(_ urlResult: Result<URL, ValidationMessage>) {
        guard case .success(let url) = urlResult else { return }
        cancelTest()
        let client = OpenAICompatibleClient(
            config: EndpointConfig(baseURL: url, model: trimmedModel, remoteConfirmed: false),
            apiKey: SettingsValidation.testConnectionKey(
                field: apiKey, storedKey: savedKey, url: url, saved: store.settings.model),
            timeout: 15)
        testState = .testing
        testTask = Task {
            let outcome: TestState
            do {
                outcome = .success(try await client.testConnection())
            } catch let error as LLMError {
                outcome = .failure(error.userMessage)
            } catch {
                outcome = .failure("The connection test failed.")
            }
            guard !Task.isCancelled else { return }
            testState = outcome
            if case .success(let ids) = outcome { offeredModels = ids }
        }
    }

    private func cancelTest() {
        testTask?.cancel()
        testTask = nil
        if testState != .idle { testState = .idle }
    }

    // MARK: Formatting

    private static func memoryText(_ bytes: UInt64) -> String {
        "\(bytes / (1 << 30)) GB memory"
    }

    private static func tierText(_ tier: RAMTier) -> String {
        switch tier {
        case .gb16: "16 GB tier"
        case .gb32: "32 GB tier"
        }
    }
}
