import Testing
@testable import TimesheetCore

struct ReferenceDetectorTests {
    let pattern = #"[A-Z][A-Z0-9]+-\d+"#

    private func detect(_ text: String, ticketRef: String? = nil, pattern: String? = nil,
                        defaultRepo: String? = "acme/app") -> DetectedReferences {
        ReferenceDetector.detect(ticketRef: ticketRef, text: text,
                                 ticketPattern: pattern ?? self.pattern, defaultRepo: defaultRepo)
    }

    @Test func findsJiraInFieldAndText() {
        #expect(detect("also DEF-2", ticketRef: "ABC-1").canonical == ["ABC-1", "DEF-2"])
    }

    @Test func findsAllPRForms() {
        let r = ReferenceDetector.detect(ticketRef: nil,
            text: "https://github.com/acme/api/pull/12/files and acme/web#7 and #3",
            ticketPattern: pattern, defaultRepo: "acme/app")
        #expect(r.canonical == ["acme/api#12", "acme/web#7", "acme/app#3"])
        #expect(r.references.first == .pullRequest(owner: "acme", repo: "api", number: 12))
    }

    @Test func bareIgnoredWithoutDefaultRepo() {
        #expect(detect("#3", defaultRepo: nil).canonical.isEmpty)
    }

    @Test func bareIgnoredWithMalformedDefaultRepo() {
        #expect(detect("#3", defaultRepo: "acme").canonical.isEmpty)
    }

    @Test func prURLIsNotAlsoJira() {
        #expect(detect("https://github.com/org/ABC-1/pull/2").canonical == ["org/ABC-1#2"])
    }

    @Test func qualifiedPRIsNotAlsoBare() {
        #expect(detect("acme/web#7").canonical == ["acme/web#7"])
    }

    @Test func deduplicatesKeepingFirstPosition() {
        #expect(detect("ABC-1 #3 #3", ticketRef: "ABC-1").canonical == ["ABC-1", "acme/app#3"])
    }

    @Test func ordersByPositionAcrossKinds() {
        #expect(detect("DEF-2 then acme/web#7 then GHI-3").canonical == ["DEF-2", "acme/web#7", "GHI-3"])
    }

    @Test func ticketRefMustMatchPattern() {
        #expect(detect("DEF-2", ticketRef: "not a ticket").canonical == ["DEF-2"])
        #expect(detect("DEF-2", ticketRef: "  ").canonical == ["DEF-2"])
    }

    @Test func capsAtFiveAndFlagsOverflow() {
        let r = detect("AX-1 BX-2 CX-3 DX-4 EX-5 FX-6")
        #expect(r.references.count == 5)
        #expect(r.overflowed)
        #expect(!detect("AX-1 BX-2 CX-3 DX-4 EX-5").overflowed)
    }

    @Test func linkedLineJoinsWithDot() {
        #expect(detect("ABC-1 and acme/web#7").linkedLine == "ABC-1 · acme/web#7")
        #expect(detect("nothing here").linkedLine == "")
    }

    @Test func ignoresHashInsideWords() {
        #expect(detect("C#7 and issue#4").canonical.isEmpty)
    }

    @Test func invalidPatternStillFindsPRs() {
        #expect(detect("acme/web#7", pattern: "[").canonical == ["acme/web#7"])
    }

    @Test func referenceServiceAndDisplayName() {
        #expect(ContextReference.jira(key: "ABC-1").service == .jira)
        #expect(ContextReference.pullRequest(owner: "o", repo: "r", number: 1).service == .github)
        #expect(IntegrationService.jira.displayName == "Jira")
        #expect(IntegrationService.github.displayName == "GitHub")
    }
}
