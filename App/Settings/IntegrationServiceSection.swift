import AppKit
import Integrations
import SwiftUI
import TimesheetCore

/// One service in Settings › Integrations: sign-in method, credentials, Test, Jira site and Disconnect.
/// Secrets go only to the token store; a stored token is never shown again.
struct IntegrationServiceSection: View {
    let service: IntegrationService

    private enum Status: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
    }

    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var session: SettingsSession
    @EnvironmentObject private var context: ContextCoordinator

    @State private var token = ""
    @State private var email = ""
    @State private var clientId = ""
    @State private var loaded = false

    @State private var status = Status.idle
    @State private var task: Task<Void, Never>?
    @State private var deviceCode: DeviceCode?
    @State private var sites: [JiraSite] = []
    @State private var pendingMethod: AuthMethod?

    private var settings: IntegrationSettings { store.settings.integrations }

    private var method: AuthMethod {
        service == .jira ? settings.jiraMethod : settings.githubMethod
    }

    private var hasSavedSignIn: Bool {
        TokenKey.allCases.contains { $0.service == service && context.tokens.get($0) != nil }
    }

    private var isBusy: Bool { status == .working }

    var body: some View {
        Section {
            Picker("Sign in with", selection: methodBinding) {
                ForEach(AuthMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            switch method {
            case .personalToken: personalTokenRows
            case .appSignIn: appSignInRows
            }
            connectionRow
            statusRow
            if service == .jira { siteRow }
        } header: {
            Text(service.displayName)
        }
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
        .alert(
            "Switch sign-in method?",
            isPresented: Binding(get: { pendingMethod != nil }, set: { if !$0 { pendingMethod = nil } }),
            presenting: pendingMethod
        ) { new in
            Button("Switch", role: .destructive) { switchMethod(to: new) }
            Button("Cancel", role: .cancel) { pendingMethod = nil }
        } message: { _ in
            Text("Switching removes the saved sign-in for \(service.displayName).")
        }
    }

    // MARK: Personal token

    @ViewBuilder
    private var personalTokenRows: some View {
        if service == .jira {
            TextField("Email", text: $email, prompt: Text("you@example.com"))
        }
        SecureField(
            service == .jira ? "API token" : "Token", text: $token,
            prompt: Text(hasToken(personalKey) ? "Saved" : "Paste token"))
        HStack {
            Button("Save", action: saveToken)
                .disabled(!canSaveToken)
            Spacer()
            Link("Open token page", destination: Self.tokenPage(service))
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(service == .jira
                 ? "Create an API token for your Atlassian account."
                 : "Grant Pull requests: Read on the repos you log.")
            if service == .jira {
                Text("Your Atlassian admin must allow API-token access to the Rovo MCP server.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var personalKey: TokenKey { service == .jira ? .jiraAPIToken : .githubToken }

    private var canSaveToken: Bool {
        let newToken = !Self.trimmed(token).isEmpty
        guard service == .jira else { return newToken }
        let newEmail = Self.trimmed(email)
        guard !newEmail.isEmpty else { return false }
        return newToken || (hasToken(.jiraAPIToken) && newEmail != (settings.jiraEmail ?? ""))
    }

    // MARK: App sign-in

    @ViewBuilder
    private var appSignInRows: some View {
        if service == .github {
            TextField("Client ID", text: $clientId, prompt: Text("Your organization's GitHub App"))
        }
        if let deviceCode {
            HStack {
                Text("Enter this code on GitHub:")
                Text(deviceCode.userCode)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Button("Copy") { Self.copy(deviceCode.userCode) }
                Spacer()
                Link("Open GitHub", destination: deviceCode.verificationURL)
            }
        }
        HStack {
            Button("Sign in", action: signIn)
                .disabled(isBusy || (service == .github && Self.trimmed(clientId).isEmpty))
            if isBusy {
                Button("Cancel", action: cancel)
            }
        }
    }

    // MARK: Status

    private var connectionRow: some View {
        HStack {
            if context.isConnected(service) {
                Label("Connected", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test", action: test)
                .disabled(isBusy || !context.isConnected(service))
            Button("Disconnect", action: disconnect)
                .disabled(!hasSavedSignIn)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .working:
            ProgressView().controlSize(.small)
        case .success(let account):
            Label(account, systemImage: "person.crop.circle.badge.checkmark")
                .foregroundStyle(.green)
                .textSelection(.enabled)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    /// Shown only when the account reaches several sites; a single site is chosen automatically.
    @ViewBuilder
    private var siteRow: some View {
        if sites.count > 1 {
            Picker("Site", selection: siteBinding) {
                if !sites.contains(where: { $0.id == settings.jiraSiteId }) {
                    Text("Choose a site").tag("")
                }
                ForEach(sites, id: \.id) { Text($0.name).tag($0.id) }
            }
        } else if context.isConnected(.jira), settings.jiraSiteId == nil {
            Text("Press Test to find your Jira site.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    private var methodBinding: Binding<AuthMethod> {
        Binding(
            get: { method },
            set: { new in
                guard new != method else { return }
                if hasSavedSignIn { pendingMethod = new } else { switchMethod(to: new) }
            })
    }

    private var siteBinding: Binding<String> {
        Binding(
            get: { settings.jiraSiteId ?? "" },
            set: { id in
                guard !id.isEmpty else { return }
                session.update { $0.integrations.jiraSiteId = id }
                context.reset(.jira)
            })
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        email = settings.jiraEmail ?? ""
        clientId = settings.githubAppClientId ?? ""
    }

    private func hasToken(_ key: TokenKey) -> Bool {
        !(context.tokens.get(key) ?? "").isEmpty
    }

    private func saveToken() {
        cancel()
        let newToken = Self.trimmed(token)
        if service == .jira {
            let newEmail = Self.trimmed(email)
            email = newEmail
            session.update { $0.integrations.jiraEmail = newEmail }
        }
        if !newToken.isEmpty {
            do {
                try context.tokens.set(newToken, for: personalKey)
            } catch {
                status = .failure("Couldn’t save the token to the Keychain.")
                return
            }
        }
        token = ""
        context.reset(service)
    }

    private func switchMethod(to new: AuthMethod) {
        pendingMethod = nil
        forget()
        session.update {
            if service == .jira { $0.integrations.jiraMethod = new } else { $0.integrations.githubMethod = new }
        }
        context.reset(service)
    }

    private func disconnect() {
        forget()
        context.reset(service)
    }

    /// Deletes every saved secret of the service, and the Jira site, which belongs to the account.
    private func forget() {
        cancel()
        token = ""
        sites = []
        Disconnect.service(service, store: context.tokens)
        if service == .jira, settings.jiraSiteId != nil {
            session.update { $0.integrations.jiraSiteId = nil }
        }
    }

    private func signIn() {
        cancel()
        status = .working
        switch service {
        case .jira:
            run {
                try await context.atlassian.signIn()
                context.reset(.jira)
                return try await testJira()
            }
        case .github:
            let id = Self.trimmed(clientId)
            clientId = id
            if id != settings.githubAppClientId { session.update { $0.integrations.githubAppClientId = id } }
            let flow = GitHubDeviceFlow(clientId: id)
            run {
                let code = try await flow.start()
                try Task.checkCancellation()
                deviceCode = code
                NSWorkspace.shared.open(code.verificationURL)
                let grant = try await flow.poll(code)
                try Task.checkCancellation()
                do {
                    try context.tokens.setOAuthToken(grant, for: .githubOAuth)
                } catch {
                    throw Failure.keychain
                }
                deviceCode = nil
                context.reset(.github)
                return try await testGitHub()
            }
        }
    }

    private func test() {
        cancel()
        status = .working
        run { service == .jira ? try await testJira() : try await testGitHub() }
    }

    /// Runs one Test or sign-in. Cancelling it shows nothing.
    private func run(_ work: @escaping @MainActor () async throws -> String) {
        task = Task {
            let outcome: Status
            do {
                outcome = .success(try await work())
            } catch is CancellationError {
                return
            } catch let error as ContextError {
                outcome = .failure(error.userMessage)
            } catch let failure as Failure {
                outcome = .failure(failure.message)
            } catch {
                outcome = .failure("Couldn’t check the \(service.displayName) account. Try again.")
            }
            guard !Task.isCancelled else { return }
            deviceCode = nil
            status = outcome
            task = nil
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        deviceCode = nil
        status = .idle
    }

    // MARK: Tests

    private func testGitHub() async throws -> String {
        let me = try await context.client(for: .github).callTool("get_me", arguments: [:])
        return Self.accountName(me, keys: ["login", "name"]) ?? "Connected"
    }

    /// Reads the account, then its sites: one is saved at once; several are offered in the picker.
    private func testJira() async throws -> String {
        let client = context.client(for: .jira)
        let me = try await client.callTool("atlassianUserInfo", arguments: [:])
        let found = try await JiraFetcher(tools: client, siteId: "").sites()
        try Task.checkCancellation()
        sites = found
        if found.count == 1, let site = found.first, site.id != settings.jiraSiteId {
            session.update { $0.integrations.jiraSiteId = site.id }
            context.reset(.jira)
        }
        if found.isEmpty { throw Failure.noSites }
        return Self.accountName(me, keys: ["name", "email"]) ?? "Connected"
    }

    /// Failures with their own wording; anything else gets a generic message.
    private enum Failure: Error {
        case keychain, noSites

        var message: String {
            switch self {
            case .keychain: "Couldn’t save the sign-in to the Keychain."
            case .noSites: "This account can’t reach any Jira site."
            }
        }
    }

    // MARK: Helpers

    /// The first non-empty string among `keys`. Never shows any other part of the reply.
    private static func accountName(_ reply: JSONValue, keys: [String]) -> String? {
        var reply = reply
        if case .string(let text) = reply, let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
            reply = decoded
        }
        guard case .object(let object) = reply else { return nil }
        for key in keys {
            if case .string(let value)? = object[key], !trimmed(value).isEmpty { return trimmed(value) }
        }
        return nil
    }

    private static func tokenPage(_ service: IntegrationService) -> URL {
        switch service {
        case .jira: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
        case .github: URL(string: "https://github.com/settings/personal-access-tokens/new")!
        }
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
