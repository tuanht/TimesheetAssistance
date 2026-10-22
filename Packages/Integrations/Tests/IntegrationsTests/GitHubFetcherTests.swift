import Foundation
import Testing
import TimesheetCore
@testable import Integrations

struct GitHubFetcherTests {
    private let ref = ContextReference.pullRequest(owner: "acme", repo: "web", number: 7)

    /// The spike's synthetic `pull_request_read` payload, with `merged` and `body` swappable.
    private static func pr(merged: Bool = false, state: String = "open", body: String = #""Retries failed uploads.""#) -> String {
        """
        {"number":7,"title":"Add retry to sync","body":\(body),"state":"\(state)","draft":false,"merged":\(merged),\
        "mergeable_state":"unknown","html_url":"https://github.com/acme/web/pull/7",\
        "user":{"login":"octo","id":1,"profile_url":"https://github.com/octo","avatar_url":"https://example.com/a.png"},\
        "assignees":["octo"],\
        "head":{"ref":"feature/retry","sha":"0000000000000000000000000000000000000000","repo":{"full_name":"acme/web","description":"Web app"}},\
        "base":{"ref":"main","sha":"1111111111111111111111111111111111111111","repo":{"full_name":"acme/web","description":"Web app"}},\
        "additions":10,"deletions":2,"changed_files":1,"commits":1,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z"}
        """
    }

    @Test func githubMapsFields() async throws {
        let tools = try FakeTools(json: Self.pr())
        let source = try await GitHubFetcher(tools: tools).fetch(ref)
        #expect(source == FetchedSource(
            reference: ref, title: "Add retry to sync", state: "open",
            detail: "feature/retry → main", body: "Retries failed uploads."))
    }

    @Test func githubMergedState() async throws {
        let tools = try FakeTools(json: Self.pr(merged: true, state: "closed"))
        let source = try await GitHubFetcher(tools: tools).fetch(ref)
        #expect(source.state == "merged")
    }

    @Test func githubClosedState() async throws {
        let tools = try FakeTools(json: Self.pr(merged: false, state: "closed"))
        let source = try await GitHubFetcher(tools: tools).fetch(ref)
        #expect(source.state == "closed")
    }

    @Test func githubNullBody() async throws {
        let tools = try FakeTools(json: Self.pr(body: "null"))
        let source = try await GitHubFetcher(tools: tools).fetch(ref)
        #expect(source.body == "")
    }

    @Test func githubNotFound() async throws {
        let tools = FakeTools(throwing: MCPToolError(
            message: "failed to get pull request: GET https://api.github.com/repos/acme/web/pulls/7: 404 Not Found []"))
        await #expect(throws: ContextError.notFound("acme/web#7")) {
            try await GitHubFetcher(tools: tools).fetch(ref)
        }
    }

    @Test func githubOtherToolErrorIsUnexpected() async throws {
        let tools = FakeTools(throwing: MCPToolError(message: "failed to get pull request: 500 Internal Server Error"))
        await #expect(throws: ContextError.unexpectedReply(.github)) {
            try await GitHubFetcher(tools: tools).fetch(ref)
        }
    }

    @Test func githubPassesClientErrorsThrough() async throws {
        let tools = FakeTools(throwing: ContextError.signInAgain(.github))
        await #expect(throws: ContextError.signInAgain(.github)) {
            try await GitHubFetcher(tools: tools).fetch(ref)
        }
    }

    @Test func githubMissingTitleIsUnexpected() async throws {
        let tools = FakeTools(returning: .object(["state": .string("open")]))
        await #expect(throws: ContextError.unexpectedReply(.github)) {
            try await GitHubFetcher(tools: tools).fetch(ref)
        }
    }

    @Test func githubRejectsJiraReference() async throws {
        let tools = try FakeTools(json: Self.pr())
        await #expect(throws: ContextError.unexpectedReply(.github)) {
            try await GitHubFetcher(tools: tools).fetch(.jira(key: "ABC-123"))
        }
        #expect(await tools.calls.isEmpty)
    }

    @Test func githubSendsOwnerRepoNumber() async throws {
        let tools = try FakeTools(json: Self.pr())
        _ = try await GitHubFetcher(tools: tools).fetch(ref)
        #expect(await tools.calls == [FakeTools.Call(name: "pull_request_read", arguments: [
            "method": .string("get"), "owner": .string("acme"), "repo": .string("web"), "pullNumber": .number(7),
        ])])
    }

    @Test func onlyIdentifiersSent() async throws {
        let github = try FakeTools(json: Self.pr())
        _ = try await GitHubFetcher(tools: github).fetch(ref)
        let jira = FakeTools(returning: .object(["fields": .object(["summary": .string("S"), "status": .object(["name": .string("Done")])])]))
        _ = try await JiraFetcher(tools: jira, siteId: "site-1").fetch(.jira(key: "ABC-123"))

        let allowed: [JSONValue] = [
            .string("ABC-123"), .string("site-1"), .string("acme"), .string("web"), .number(7), .string("get"),
        ]
        let calls = await github.calls + jira.calls
        #expect(!calls.isEmpty)
        for call in calls {
            for value in call.arguments.values {
                #expect(allowed.contains(value), "unexpected argument in \(call.name)")
            }
        }
    }
}
