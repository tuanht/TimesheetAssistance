import Foundation
import Testing
@testable import TimesheetCore

struct SettingsValidationTests {
    // MARK: Template

    @Test func separatorRejectsOnlyEmpty() {
        #expect(SettingsValidation.separatorError("") != nil)
        #expect(SettingsValidation.separatorError(" ") == nil)
        #expect(SettingsValidation.separatorError("\t") == nil)
        #expect(SettingsValidation.separatorError(";") == nil)
        #expect(SettingsValidation.separatorError(" | ") == nil)
    }

    @Test func separatorSubstituteRejectsEmpty() {
        #expect(SettingsValidation.separatorSubstituteError("", separator: " | ") != nil)
        #expect(SettingsValidation.separatorSubstituteError("/", separator: " | ") == nil)
    }

    @Test func separatorSubstituteRejectsContainingSeparator() {
        #expect(SettingsValidation.separatorSubstituteError(" | ", separator: " | ") != nil)
        #expect(SettingsValidation.separatorSubstituteError("a;b", separator: ";") != nil)
        #expect(SettingsValidation.separatorSubstituteError(" / ", separator: "\t") == nil)
        // The renderer keeps the separator's padding around the substitute, so its core must not appear either.
        #expect(SettingsValidation.separatorSubstituteError("|", separator: " | ") != nil)
        #expect(SettingsValidation.separatorSubstituteError("/", separator: " | ") == nil)
        #expect(SettingsValidation.separatorSubstituteError("/", separator: "\t") == nil)
    }

    @Test func formatRejectsBlank() {
        #expect(SettingsValidation.formatError(" ") != nil)
        #expect(SettingsValidation.formatError("yyyy-MM-dd") == nil)
    }

    @Test func ticketPatternRejectsInvalidRegex() {
        #expect(SettingsValidation.ticketPatternError("[A-Z") != nil)
        #expect(SettingsValidation.ticketPatternError("") != nil)
        #expect(SettingsValidation.ticketPatternError(#"[A-Z][A-Z0-9]+-\d+"#) == nil)
    }

    @Test func maxDescriptionLengthMustBePositiveInteger() {
        #expect(SettingsValidation.maxDescriptionLength("80") == .success(80))
        #expect(SettingsValidation.maxDescriptionLength(" 80 ") == .success(80))
        #expect(SettingsValidation.maxDescriptionLength("0").isFailure)
        #expect(SettingsValidation.maxDescriptionLength("-3").isFailure)
        #expect(SettingsValidation.maxDescriptionLength("abc").isFailure)
        #expect(SettingsValidation.maxDescriptionLength("").isFailure)
    }

    @Test func fieldsNeedAtLeastOne() {
        #expect(SettingsValidation.fieldsError([]) != nil)
        #expect(SettingsValidation.fieldsError([.description]) == nil)
    }

    // MARK: Lists

    @Test func listErrorsFlagBlankAndLaterDuplicates() {
        let errors = SettingsValidation.listErrors(["Dev", " ", "dev ", "Test", "DEV"])
        #expect(errors[0] == nil)
        #expect(errors[1] != nil)
        #expect(errors[2] != nil)
        #expect(errors[3] == nil)
        #expect(errors[4] != nil)
    }

    @Test func listErrorsAllNilForValidList() {
        #expect(SettingsValidation.listErrors(["A", "B"]) == [nil, nil])
    }

    @Test func listMustKeepAtLeastOneValue() {
        #expect(SettingsValidation.listCountError([]) != nil)
        #expect(SettingsValidation.listCountError(["Only"]) == nil)
    }

    @Test func newListValueRejectsBlankAndDuplicates() {
        let existing = ["Meeting", "Testing"]
        #expect(SettingsValidation.newListValueError("", existing: existing) != nil)
        #expect(SettingsValidation.newListValueError("  meeting ", existing: existing) != nil)
        #expect(SettingsValidation.newListValueError("Support", existing: existing) == nil)
    }

    // MARK: Working hours

    private func hours(_ s: String, _ e: String, _ ls: String, _ le: String, rounding: Int = 15) -> WorkingHours {
        WorkingHours(start: ClockTime(s)!, end: ClockTime(e)!, lunchStart: ClockTime(ls)!,
                     lunchEnd: ClockTime(le)!, roundingMinutes: rounding)
    }

    @Test func defaultWorkingHoursAreValid() {
        #expect(SettingsValidation.workingHoursError(.default) == nil)
    }

    @Test func endMustBeAfterStart() {
        #expect(SettingsValidation.workingHoursError(hours("09:00", "09:00", "09:00", "09:00")) != nil)
        #expect(SettingsValidation.workingHoursError(hours("10:00", "09:00", "09:30", "09:30")) != nil)
    }

    @Test func lunchMustLieWithinDayAndBeOrdered() {
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "08:30", "09:30")) != nil)
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "16:30", "17:30")) != nil)
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "13:00", "12:00")) != nil)
        // Equal lunch bounds mean no lunch; lunch may touch the day's edges.
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "12:00", "12:00")) == nil)
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "09:00", "17:00")) == nil)
    }

    @Test func roundingMustBeOffered() {
        #expect(SettingsValidation.roundingOptions == [5, 10, 15, 30])
        #expect(SettingsValidation.workingHoursError(hours("09:00", "17:00", "12:00", "13:00", rounding: 7)) != nil)
    }

    @Test func clockTimeParsesHHmm() {
        #expect(SettingsValidation.clockTime("9:05") == .success(ClockTime(9, 5)))
        #expect(SettingsValidation.clockTime(" 17:30 ") == .success(ClockTime(17, 30)))
        #expect(SettingsValidation.clockTime("25:00").isFailure)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { true } else { false }
    }
}

struct EndpointValidationTests {
    private func urlError(_ text: String) -> String? {
        if case .failure(let m) = SettingsValidation.endpointURL(text) { return m.text }
        return nil
    }

    @Test func acceptsHttpLocalAndHttpsRemote() throws {
        #expect(try SettingsValidation.endpointURL("http://localhost:11434").get().absoluteString == "http://localhost:11434")
        #expect(try SettingsValidation.endpointURL("  https://api.example.com/v1 ").get().host() == "api.example.com")
        #expect(urlError("http://192.168.1.5:1234/v1") == nil)
    }

    @Test func rejectsBlankBadSchemeAndMissingHost() {
        #expect(urlError("") == "Enter a base URL.")
        #expect(urlError("   ") == "Enter a base URL.")
        #expect(urlError("ftp://localhost") == "Use a URL starting with http:// or https://.")
        #expect(urlError("localhost:1234") == "Use a URL starting with http:// or https://.")
        #expect(urlError("http://") == "The URL needs a host.")
        #expect(urlError("https:///v1") == "The URL needs a host.")
    }

    @Test func rejectsRemotePlainHttp() {
        #expect(urlError("http://api.example.com") == "Remote endpoints must use https.")
        #expect(urlError("HTTP://8.8.8.8") == "Remote endpoints must use https.")
    }

    @Test func modelNameMustNotBeBlank() {
        #expect(SettingsValidation.endpointModelError("") == "Enter a model name.")
        #expect(SettingsValidation.endpointModelError("  ") == "Enter a model name.")
        #expect(SettingsValidation.endpointModelError("qwen3:8b") == nil)
    }

    @Test func localNeverNeedsConfirmation() {
        let url = URL(string: "http://localhost:11434")!
        #expect(!SettingsValidation.needsRemoteConfirmation(url, saved: .none))
    }

    @Test func remoteNeedsConfirmationUnlessSameHostAlreadyConfirmed() {
        let url = URL(string: "https://api.example.com/v1")!
        let confirmed = ModelSelection.endpoint(EndpointConfig(
            baseURL: URL(string: "https://API.example.com")!, model: "m", remoteConfirmed: true))
        let unconfirmed = ModelSelection.endpoint(EndpointConfig(
            baseURL: URL(string: "https://api.example.com")!, model: "m", remoteConfirmed: false))
        let otherHost = ModelSelection.endpoint(EndpointConfig(
            baseURL: URL(string: "https://other.example.com")!, model: "m", remoteConfirmed: true))

        #expect(SettingsValidation.needsRemoteConfirmation(url, saved: .none))
        #expect(SettingsValidation.needsRemoteConfirmation(url, saved: .local(repoId: "x")))
        #expect(SettingsValidation.needsRemoteConfirmation(url, saved: unconfirmed))
        #expect(SettingsValidation.needsRemoteConfirmation(url, saved: otherHost))
        #expect(!SettingsValidation.needsRemoteConfirmation(url, saved: confirmed))
    }

    @Test func rejectsCredentialsInURL() {
        let message = "Don't put credentials in the URL. Use the API key field."
        #expect(urlError("https://user:pass@api.example.com") == message)
        #expect(urlError("https://user@api.example.com") == message)
        #expect(urlError("http://:secret@localhost:1234") == message)
    }

    // MARK: Test connection key

    private let saved = ModelSelection.endpoint(EndpointConfig(
        baseURL: URL(string: "https://API.example.com")!, model: "m", remoteConfirmed: true))

    @Test func sameHostSendsStoredKey() {
        let url = URL(string: "https://api.example.com/v1")!
        #expect(SettingsValidation.testConnectionKey(field: "stored", storedKey: "stored", url: url, saved: saved) == "stored")
    }

    @Test func differentHostWithUntouchedFieldSendsNoKey() {
        let url = URL(string: "https://evil.example.net")!
        #expect(SettingsValidation.testConnectionKey(field: "stored", storedKey: "stored", url: url, saved: saved) == nil)
        #expect(SettingsValidation.testConnectionKey(field: "stored", storedKey: "stored", url: url, saved: .none) == nil)
    }

    @Test func typedKeyIsSentToAnyHost() {
        let url = URL(string: "https://evil.example.net")!
        #expect(SettingsValidation.testConnectionKey(field: "typed", storedKey: "stored", url: url, saved: saved) == "typed")
        #expect(SettingsValidation.testConnectionKey(field: "typed", storedKey: "", url: url, saved: .none) == "typed")
    }

    @Test func emptyFieldSendsNoKey() {
        let url = URL(string: "https://api.example.com")!
        #expect(SettingsValidation.testConnectionKey(field: "", storedKey: "stored", url: url, saved: saved) == nil)
    }
}
