import Testing
@testable import TimesheetCore

struct ContextPolicyTests {
    @Test func sameRefsWithSummaryDoesNothing() {
        #expect(ContextPolicy.onSave(current: ["ABC-1"], stored: ["ABC-1"], hasSummary: true, edited: false) == ContextAction.none)
    }

    @Test func sameRefsWithoutSummaryFetches() {
        #expect(ContextPolicy.onSave(current: ["ABC-1"], stored: ["ABC-1"], hasSummary: false, edited: false) == .fetch)
    }

    @Test func changedRefsFetch() {
        #expect(ContextPolicy.onSave(current: ["ABC-2"], stored: ["ABC-1"], hasSummary: true, edited: false) == .fetch)
        #expect(ContextPolicy.onSave(current: ["ABC-1"], stored: nil, hasSummary: false, edited: false) == .fetch)
    }

    @Test func changedRefsWithEditConfirm() {
        #expect(ContextPolicy.onSave(current: ["ABC-2"], stored: ["ABC-1"], hasSummary: true, edited: true) == .confirmReplace)
    }

    @Test func removedRefsClearUneditedSummary() {
        #expect(ContextPolicy.onSave(current: [], stored: ["ABC-1"], hasSummary: true, edited: false) == .clear)
    }

    @Test func removedRefsKeepEditedSummary() {
        #expect(ContextPolicy.onSave(current: [], stored: ["ABC-1"], hasSummary: true, edited: true) == ContextAction.none)
        #expect(ContextPolicy.onSave(current: [], stored: nil, hasSummary: false, edited: false) == ContextAction.none)
    }

    @Test func refreshEditedConfirms() {
        #expect(ContextPolicy.onRefresh(current: ["ABC-1"], edited: true) == .confirmReplace)
        #expect(ContextPolicy.onRefresh(current: ["ABC-1"], edited: false) == .fetch)
    }

    @Test func refreshEmptyDoesNothing() {
        #expect(ContextPolicy.onRefresh(current: [], edited: true) == ContextAction.none)
    }

    @Test func applyRejectsWhenRefsChanged() {
        #expect(!ContextPolicy.shouldApply(jobRefs: ["ABC-1"], currentRefs: ["ABC-2"], editedSinceStart: false))
        #expect(!ContextPolicy.shouldApply(jobRefs: ["ABC-1"], currentRefs: nil, editedSinceStart: false))
    }

    @Test func applyRejectsWhenEditedDuringJob() {
        #expect(!ContextPolicy.shouldApply(jobRefs: ["ABC-1"], currentRefs: ["ABC-1"], editedSinceStart: true))
    }

    @Test func applyAcceptsUnchanged() {
        #expect(ContextPolicy.shouldApply(jobRefs: ["ABC-1"], currentRefs: ["ABC-1"], editedSinceStart: false))
    }
}
