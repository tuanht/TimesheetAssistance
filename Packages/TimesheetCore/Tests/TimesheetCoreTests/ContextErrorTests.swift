import Testing
@testable import TimesheetCore

struct ContextErrorTests {
    @Test func notConnected() {
        #expect(ContextError.notConnected(.jira).userMessage == "Jira not connected")
        #expect(ContextError.notConnected(.github).userMessage == "GitHub not connected")
    }

    @Test func notFound() {
        #expect(ContextError.notFound("ABC-123").userMessage == "Couldn't find ABC-123 in Jira.")
        #expect(ContextError.notFound("acme/web#7").userMessage == "Couldn't find acme/web#7 on GitHub.")
    }

    @Test func unreachable() {
        #expect(ContextError.unreachable(.jira).userMessage
            == "Couldn't reach Jira. Check your connection and try again.")
        #expect(ContextError.unreachable(.github).userMessage
            == "Couldn't reach GitHub. Check your connection and try again.")
    }

    @Test func signInAgain() {
        #expect(ContextError.signInAgain(.jira).userMessage == "Sign in to Jira again in Settings › Integrations.")
        #expect(ContextError.signInAgain(.github).userMessage == "Sign in to GitHub again in Settings › Integrations.")
    }

    @Test func notApprovedGitHub() {
        #expect(ContextError.notApproved(.github).userMessage
            == "Your organization hasn't approved this app for GitHub. Ask an admin, or switch sign-in method in Settings › Integrations.")
    }

    @Test func notApprovedJira() {
        #expect(ContextError.notApproved(.jira).userMessage
            == "Your organization hasn't enabled this for Jira. Ask an admin, or switch sign-in method in Settings › Integrations.")
    }

    @Test func unexpectedReply() {
        #expect(ContextError.unexpectedReply(.jira).userMessage
            == "Jira sent a reply the app couldn't read. Try again later.")
        #expect(ContextError.unexpectedReply(.github).userMessage
            == "GitHub sent a reply the app couldn't read. Try again later.")
    }

    @Test func toolNotAllowed() {
        let message = ContextError.toolNotAllowed("createJiraIssue").userMessage
        #expect(message == "The app tried an action it isn't allowed to use.")
    }

    @Test func finishedStatusKeepsFailuresAndNotesApart() {
        let status = ContextStatus.finished(
            failures: [ContextError.notFound("acme/web#7").userMessage, "Couldn’t save the summary. Try again."],
            notes: [ContextError.notConnected(.jira).userMessage])
        #expect(status.failureText == "Couldn't find acme/web#7 on GitHub.\nCouldn’t save the summary. Try again.")
        #expect(status.noteText == "Jira not connected")
    }

    @Test func notesAloneHaveNoFailureText() {
        let status = ContextStatus.finished(failures: [], notes: [ContextError.notConnected(.jira).userMessage])
        #expect(status.failureText == nil)
        #expect(status.noteText == "Jira not connected")
    }

    @Test func progressHasNoFailureOrNoteText() {
        #expect(ContextStatus.summarizing.failureText == nil)
        #expect(ContextStatus.fetching("ABC-123").noteText == nil)
    }

    @Test func statusTextFetchingAndSummarizing() {
        #expect(ContextStatus.fetching("ABC-123").text == "Fetching ABC-123…")
        #expect(ContextStatus.summarizing.text == "Summarizing…")
    }
}
