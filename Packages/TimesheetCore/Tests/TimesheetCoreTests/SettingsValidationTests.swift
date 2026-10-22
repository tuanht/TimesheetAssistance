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
        // Only the exact separator string counts: "|" does not contain " | ".
        #expect(SettingsValidation.separatorSubstituteError("|", separator: " | ") == nil)
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
