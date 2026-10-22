import Foundation
import Testing
import TimesheetCore
@testable import Integrations

struct JiraFetcherTests {
    private let ref = ContextReference.jira(key: "ABC-123")

    private static func issue(description: String = #""Sync drops uploads on retry.""#) -> String {
        """
        {"id":"10001","key":"ABC-123","fields":{"summary":"Fix upload retry",\
        "status":{"name":"In Progress","statusCategory":{"key":"indeterminate"}},\
        "issuetype":{"name":"Bug","subtask":false},"description":\(description)}}
        """
    }

    private func fetcher(_ tools: FakeTools) -> JiraFetcher {
        JiraFetcher(tools: tools, siteId: "site-1")
    }

    @Test func jiraMapsFields() async throws {
        let tools = try FakeTools(json: Self.issue())
        let source = try await fetcher(tools).fetch(ref)
        #expect(source == FetchedSource(
            reference: ref, title: "Fix upload retry", state: "In Progress",
            detail: "Bug", body: "Sync drops uploads on retry."))
    }

    @Test func jiraFlattensADF() async throws {
        let adf = """
        {"type":"doc","version":1,"content":[\
        {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Steps"}]},\
        {"type":"paragraph","content":[{"type":"text","text":"Upload a "},{"type":"text","text":"file","marks":[{"type":"strong"}]},\
        {"type":"hardBreak"},{"type":"text","text":"then go offline."}]},\
        {"type":"bulletList","content":[\
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"First retry fails"}]}]},\
        {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Second never runs"}]}]}]},\
        {"type":"paragraph","content":[]},\
        {"type":"codeBlock","content":[{"type":"text","text":"retry(count: 3)"}]}]}
        """
        let tools = try FakeTools(json: Self.issue(description: adf))
        let source = try await fetcher(tools).fetch(ref)
        #expect(source.body == """
            Steps
            Upload a file
            then go offline.
            First retry fails
            Second never runs
            retry(count: 3)
            """)
    }

    @Test func jiraMissingDescriptionIsEmpty() async throws {
        let tools = try FakeTools(json: Self.issue(description: "null"))
        let source = try await fetcher(tools).fetch(ref)
        #expect(source.body == "")
    }

    @Test(arguments: [
        "Issue does not exist or you do not have permission to see it.",
        "Request failed with status 404",
        "Issue Not Found",
    ])
    func jiraNotFound(message: String) async throws {
        let tools = FakeTools(throwing: MCPToolError(message: message))
        await #expect(throws: ContextError.notFound("ABC-123")) {
            try await fetcher(tools).fetch(ref)
        }
    }

    @Test func jiraToolNotFoundIsNotApproved() async throws {
        let tools = FakeTools(throwing: MCPToolError(message: "MCP error -32602: Tool getJiraIssue not found"))
        await #expect(throws: ContextError.notApproved(.jira)) {
            try await fetcher(tools).fetch(ref)
        }
    }

    @Test func jiraOtherToolErrorIsUnexpected() async throws {
        let tools = FakeTools(throwing: MCPToolError(message: "Internal error"))
        await #expect(throws: ContextError.unexpectedReply(.jira)) {
            try await fetcher(tools).fetch(ref)
        }
    }

    @Test func jiraMissingSummaryIsUnexpected() async throws {
        let tools = FakeTools(returning: .object(["fields": .object(["status": .object(["name": .string("Done")])])]))
        await #expect(throws: ContextError.unexpectedReply(.jira)) {
            try await fetcher(tools).fetch(ref)
        }
    }

    @Test func jiraRejectsPullRequestReference() async throws {
        let tools = try FakeTools(json: Self.issue())
        await #expect(throws: ContextError.unexpectedReply(.jira)) {
            try await fetcher(tools).fetch(.pullRequest(owner: "acme", repo: "web", number: 7))
        }
        #expect(await tools.calls.isEmpty)
    }

    @Test func jiraSendsKeyAndSite() async throws {
        let tools = try FakeTools(json: Self.issue())
        _ = try await fetcher(tools).fetch(ref)
        #expect(await tools.calls == [FakeTools.Call(name: "getJiraIssue", arguments: [
            "cloudId": .string("site-1"), "issueIdOrKey": .string("ABC-123"),
        ])])
    }

    @Test func jiraListsSites() async throws {
        let tools = try FakeTools(json: """
            [{"id":"site-1","name":"acme","url":"https://acme.atlassian.net","scopes":["read:jira-work"],"avatarUrl":"https://example.com/a.png"},\
            {"id":"site-2","name":"acme-labs","url":"https://acme-labs.atlassian.net","scopes":[]}]
            """)
        let sites = try await fetcher(tools).sites()
        #expect(sites == [
            JiraSite(id: "site-1", name: "acme", url: URL(string: "https://acme.atlassian.net")!),
            JiraSite(id: "site-2", name: "acme-labs", url: URL(string: "https://acme-labs.atlassian.net")!),
        ])
        #expect(await tools.calls == [FakeTools.Call(name: "getAccessibleAtlassianResources", arguments: [:])])
    }

    @Test func jiraSitesToolNotFoundIsNotApproved() async throws {
        let tools = FakeTools(throwing: MCPToolError(
            message: "MCP error -32602: Tool getAccessibleAtlassianResources not found"))
        await #expect(throws: ContextError.notApproved(.jira)) {
            try await fetcher(tools).sites()
        }
    }
}
