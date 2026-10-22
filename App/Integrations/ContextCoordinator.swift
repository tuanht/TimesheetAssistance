import Foundation
import Integrations
import LocalModels
import SwiftData
import TimesheetCore

/// Fetches each entry's referenced tickets and PRs and summarizes them with the compile model,
/// one job at a time. Status lives in memory only; only the summary and the refs it was built from are saved.
@MainActor
final class ContextCoordinator: ObservableObject {
    static let overflowMessage = "Only the first \(ReferenceDetector.maxReferences) references were fetched."

    @Published private(set) var status: [UUID: ContextStatus] = [:]
    /// Services whose selected sign-in method has its secrets stored. Cached so views never read
    /// the Keychain while rendering; recomputed by `reset(_:)`.
    @Published private(set) var connected: Set<IntegrationService> = []

    /// For the Integrations tab: saving tokens, disconnecting and Jira sign-in.
    let tokens: any TokenStore
    let atlassian: AtlassianOAuth

    private let session: SettingsSession
    private let models: MLXModelManager
    private var clients: [IntegrationService: ServiceClient] = [:]
    private var queue: [Job] = []
    private var running: Job?
    private var worker: Task<Void, Never>?

    private struct Job {
        let id: UUID
        let detected: DetectedReferences
        /// The entry's summary when the job was queued, to tell whether the user edited it since.
        let summary: String?
        let edited: Bool
        let context: ModelContext

        /// Same entry, same refs and same summary state. A job started before the user edited the summary
        /// would be rejected at apply, so it doesn't count as a repeat.
        func repeats(_ other: Job) -> Bool {
            id == other.id && detected.canonical == other.detected.canonical
                && summary == other.summary && edited == other.edited
        }
    }

    /// One MCP client per service, rebuilt only when what its credentials depend on changes.
    private struct ServiceClient {
        let key: String
        let client: MCPClient
    }

    /// A summary failure already worded for the user.
    private struct SummaryFailure: Error {
        let message: String
    }

    init(session: SettingsSession, models: MLXModelManager, tokens: any TokenStore = KeychainTokenStore()) {
        self.session = session
        self.models = models
        self.tokens = tokens
        self.atlassian = AtlassianOAuth(store: tokens, presenter: WebAuthSignInPresenter())
        connected = storedConnections()
    }

    private var integrations: IntegrationSettings { session.store.settings.integrations }

    // MARK: - Entry actions

    /// Entries in `ids` still fetching or summarizing.
    func pendingCount(in ids: Set<UUID>) -> Int {
        ids.filter { id in
            switch status[id] {
            case .fetching, .summarizing: true
            default: false
            }
        }.count
    }

    /// The entry's references under the current ticket pattern and default repo.
    func detect(_ entry: LogEntry) -> DetectedReferences {
        let settings = session.store.settings
        return ReferenceDetector.detect(
            ticketRef: entry.ticketRef, text: entry.text,
            ticketPattern: settings.template.ticketPattern, defaultRepo: settings.integrations.defaultRepo)
    }

    /// Queues a fetch of the entry's current refs, unless the same job is already queued or running.
    /// Nothing is written to the entry until the summary is applied.
    func enqueue(_ entry: LogEntry) {
        guard let context = entry.modelContext else { return }
        let detected = detect(entry)
        let job = Job(id: entry.id, detected: detected, summary: entry.contextSummary,
                      edited: entry.contextEdited, context: context)
        if running?.repeats(job) == true || queue.contains(where: { $0.repeats(job) }) { return }
        queue.removeAll { $0.id == job.id }

        guard let first = detected.references.first(where: { isConnected($0.service) }) else {
            // Nothing to fetch. Not-connected refs are reported only when another service is connected.
            if detected.references.isEmpty || !isAnyConnected {
                if running?.id != job.id { status[job.id] = nil }
                return
            }
            enqueueJob(job, status: nil)
            return
        }
        enqueueJob(job, status: .fetching(first.canonical))
    }

    /// The `.clear` action: forget the summary and its refs.
    func clear(_ entry: LogEntry) {
        queue.removeAll { $0.id == entry.id }
        status[entry.id] = nil
        entry.contextSummary = nil
        entry.contextRefs = nil
        entry.contextEdited = false
        entry.contextUpdatedAt = nil
        try? entry.modelContext?.save()
    }

    // MARK: - Connections

    /// True when the selected sign-in method has its secrets stored. Reads the cache, not the Keychain.
    func isConnected(_ service: IntegrationService) -> Bool {
        connected.contains(service)
    }

    var isAnyConnected: Bool { !connected.isEmpty }

    private func storedConnections() -> Set<IntegrationService> {
        Set(IntegrationService.allCases.filter(hasStoredSignIn))
    }

    private func hasStoredSignIn(_ service: IntegrationService) -> Bool {
        switch service {
        case .jira:
            switch integrations.jiraMethod {
            case .personalToken: hasToken(.jiraAPIToken) && !jiraEmail.isEmpty
            case .appSignIn: hasToken(.jiraOAuth)
            }
        case .github:
            switch integrations.githubMethod {
            case .personalToken: hasToken(.githubToken)
            case .appSignIn: hasToken(.githubOAuth)
            }
        }
    }

    /// The service's MCP client for the current sign-in method. The Integrations tab uses it for Test.
    func client(for service: IntegrationService) -> MCPClient {
        let key = clientKey(service)
        if let existing = clients[service], existing.key == key { return existing.client }
        let client = MCPClient(server: service == .jira ? .atlassian : .github, credentials: credentials(for: service))
        clients[service] = ServiceClient(key: key, client: client)
        return client
    }

    /// Call after tokens or the sign-in method change (save, sign-in, disconnect, switch): drops the
    /// client and its MCP session, and re-reads which services are connected.
    func reset(_ service: IntegrationService) {
        clients[service] = nil
        connected = storedConnections()
        objectWillChange.send()
    }

    private var jiraEmail: String { (integrations.jiraEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private func hasToken(_ key: TokenKey) -> Bool {
        guard let value = tokens.get(key) else { return false }
        return !value.isEmpty
    }

    private func clientKey(_ service: IntegrationService) -> String {
        switch service {
        case .jira: "\(integrations.jiraMethod.rawValue)|\(integrations.jiraMethod == .personalToken ? jiraEmail : "")"
        case .github: integrations.githubMethod.rawValue
        }
    }

    private func credentials(for service: IntegrationService) -> any CredentialProvider {
        switch service {
        case .jira:
            switch integrations.jiraMethod {
            case .personalToken: PersonalTokenCredentials(service: .jira, email: jiraEmail, store: tokens)
            case .appSignIn: atlassian.credentials()
            }
        case .github:
            switch integrations.githubMethod {
            case .personalToken: PersonalTokenCredentials(service: .github, email: nil, store: tokens)
            case .appSignIn: StoredOAuthCredentials(key: .githubOAuth, service: .github, store: tokens)
            }
        }
    }

    /// A Jira fetcher for the saved site. With no site saved, a single reachable site is adopted and saved.
    func jiraFetcher() async throws -> JiraFetcher {
        let client = client(for: .jira)
        if let siteId = integrations.jiraSiteId, !siteId.isEmpty { return JiraFetcher(tools: client, siteId: siteId) }
        let sites = try await JiraFetcher(tools: client, siteId: "").sites()
        // Several sites: the user picks one in Settings.
        guard sites.count == 1, let site = sites.first else { throw ContextError.notConnected(.jira) }
        session.update { $0.integrations.jiraSiteId = site.id }
        return JiraFetcher(tools: client, siteId: site.id)
    }

    private func fetcher(for service: IntegrationService) async throws -> any ContextFetcher {
        switch service {
        case .jira: try await jiraFetcher()
        case .github: GitHubFetcher(tools: client(for: .github))
        }
    }

    // MARK: - Queue

    private func enqueueJob(_ job: Job, status initial: ContextStatus?) {
        if let initial { status[job.id] = initial }
        queue.append(job)
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            running = job
            await run(job)
            running = nil
        }
        worker = nil
    }

    private func run(_ job: Job) async {
        guard isAnyConnected else { return finish(job, failures: []) }
        var failures: [String] = []
        func fail(_ message: String) { if !failures.contains(message) { failures.append(message) } }

        var sources: [FetchedSource] = []
        var fetchers: [IntegrationService: Result<any ContextFetcher, Error>] = [:]
        for reference in job.detected.references {
            let service = reference.service
            guard isConnected(service) else {
                fail(ContextError.notConnected(service).userMessage)
                continue
            }
            guard update(job, .fetching(reference.canonical)) else { return }
            // One fetcher per service per job, so a failed Jira site lookup isn't repeated per ref.
            let made: Result<any ContextFetcher, Error>
            if let cached = fetchers[service] {
                made = cached
            } else {
                do { made = .success(try await fetcher(for: service)) } catch { made = .failure(error) }
                fetchers[service] = made
            }
            do {
                sources.append(try await made.get().fetch(reference))
            } catch {
                fail(Self.message(for: error, service: service))
            }
        }
        guard !sources.isEmpty else { return finish(job, failures: failures) }

        guard update(job, .summarizing) else { return }
        let summary: String
        do {
            summary = try await summarize(sources)
        } catch {
            fail(Self.message(forSummary: error))
            return finish(job, failures: failures)
        }
        apply(summary, job: job, failures: &failures)
        finish(job, failures: failures)
    }

    private func summarize(_ sources: [FetchedSource]) async throws -> String {
        let plan = ClientPlan.resolve(session.store.settings.model, isDownloaded: models.isDownloaded)
        guard let client = LLMClientFactory.make(plan, models: models) else {
            if case .unavailable(let reason) = plan { throw SummaryFailure(message: reason.message) }
            throw SummaryFailure(message: Self.summaryFailed)
        }
        let prompt = ContextPromptBuilder.build(sources)
        let reply = try await ModelGate.shared.run {
            try await client.complete(system: prompt.system, user: prompt.user)
        }
        return try SummaryParser.clean(reply)
    }

    /// Writes the summary and the refs it was built from, unless the entry was deleted, its refs changed
    /// or the user edited it meanwhile.
    private func apply(_ summary: String, job: Job, failures: inout [String]) {
        guard let entry = Self.entry(job.id, in: job.context) else {
            failures = []
            return
        }
        let editedSinceStart = entry.contextSummary != job.summary || entry.contextEdited != job.edited
        guard ContextPolicy.shouldApply(
            jobRefs: job.detected.canonical, currentRefs: detect(entry).canonical, editedSinceStart: editedSinceStart)
        else {
            // A stale result: its failures don't describe the entry any more.
            failures = []
            return
        }
        let previous = (entry.contextSummary, entry.contextRefs, entry.contextEdited, entry.contextUpdatedAt)
        entry.contextSummary = summary
        entry.contextRefs = job.detected.canonical
        entry.contextEdited = false
        entry.contextUpdatedAt = Date()
        do {
            try job.context.save()
        } catch {
            // Undo only this job's change; a rollback would also discard unrelated unsaved edits.
            (entry.contextSummary, entry.contextRefs, entry.contextEdited, entry.contextUpdatedAt) = previous
            failures.append("Couldn’t save the summary. Try again.")
        }
    }

    private func finish(_ job: Job, failures: [String]) {
        update(job, failures.isEmpty ? nil : .failed(failures))
    }

    /// Writes a running job's status. Returns false when the job is stale: a newer job for the entry
    /// is queued (it owns the status), or the entry was deleted or its refs changed (status removed).
    /// Refs are re-detected from the entry's ticket and text, since stored refs change only on apply.
    @discardableResult
    private func update(_ job: Job, _ new: ContextStatus?) -> Bool {
        guard !queue.contains(where: { $0.id == job.id }) else { return false }
        guard let entry = Self.entry(job.id, in: job.context), detect(entry).canonical == job.detected.canonical else {
            status[job.id] = nil
            return false
        }
        status[job.id] = new
        return true
    }

    private static func entry(_ id: UUID, in context: ModelContext) -> LogEntry? {
        var descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Messages (never server text, tokens or model output)

    private static let summaryFailed = "Couldn’t summarize the details. Try again."

    private static func message(for error: Error, service: IntegrationService) -> String {
        ((error as? ContextError) ?? .unexpectedReply(service)).userMessage
    }

    private static func message(forSummary error: Error) -> String {
        switch error {
        case let failure as SummaryFailure: failure.message
        case let error as LLMError: error.userMessage
        default: summaryFailed
        }
    }
}
