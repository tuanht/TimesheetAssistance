# Periods, Calendar Picker and Ticket Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five user-requested improvements:
1. Show the app name as "Timesheet Assistant".
2. Pick dates from a calendar that shows a month.
3. Rename the "Ticket / task" type to "Ticket".
4. Detect ticket numbers reliably.
5. View the daily log by day, week or month, and compile a day, week, month or custom range.

**Architecture:** Pure period and range logic goes in TimesheetCore with tests:
- `PeriodKind`, `DayRange`, `Period` for ranges and labels.
- `TicketDetector` for tickets.
- Range queries on `Store` and a multi-day `LineRenderer.render(days:)`.

The app layer gets two shared views, `PeriodBar` and `CalendarButton`. Compile stays one model call per day, and each day is still saved as its own `CompiledDay`. A range compile runs the days in order.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md` (binding for the existing rules). These changes come from the user's request, and the user opted out of a design pass. The decisions below are the controller's calls.

## Global Constraints

- Days are matched by `DayKey` (`yyyy-MM-dd`), never by a `Date` instant.
- **Flag, don't fix silently:**
  - Never truncate a description.
  - The validator only flags problems.
- `LineRenderer` output has lines only: no header and no markdown. A multi-day render is each day's lines, joined with `\n`, with no day headers. The template's `date` field identifies each day.
- User-facing error text: plain English, short, actionable.
- One responsibility per file, and small pure functions. Core logic is TDD with Swift Testing (`import Testing`).
- **No new network calls.** No new dependencies.
- **Core tests:** `swift test --package-path Packages/TimesheetCore`.
- **App build:** `xcodegen generate && xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build`.
- Do not stage or commit `CLAUDE.md`. It holds the user's uncommitted edit.

## Review Focus

1. **Week bounds follow `calendar.firstWeekday`,** including weeks that cross a month or year. Covered by Task 2 tests (Sunday-first, Monday-first, Dec 31).
2. **Custom range picked "backwards"** (To before From) is normalized, not empty. Covered by Task 2 `rangeNormalizesReversedDates`.
3. **Invalid or empty ticket pattern** in Settings: detection returns nil and doesn't crash. With several tickets in the text, the first wins. Covered by Task 1 tests.
4. **An entry moved to another day in the editor** leaves the old day and appears under the new one. Covered by Task 3 `moveChangesDayKey`, and by the `@Query` on range keys in Task 5.
5. **One day failing mid-range.** Days already compiled stay saved, and the error names the failing day. Owned by Task 6 (app; checked by reading the code in review).

---

### Task 1: Rename "Ticket / task" and detect tickets in entry text

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/EntrySnapshot.swift:8`
- Create: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/TicketDetector.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/Compiler.swift` (`LineFields`)
- Test: `Packages/TimesheetCore/Tests/TimesheetCoreTests/TicketDetectorTests.swift` (create), `CompilerTests.swift` (add)

**Interfaces:**
- Produces: `public enum TicketDetector { public static func firstTicket(in text: String, pattern: String) -> String? }`

**Ticket precedence for a line** (the controller's call):
1. The entry's own `ticketRef`, if not blank.
2. Otherwise, the first match of `settings.template.ticketPattern` in the entry text.
3. Otherwise, the model's `ticket`, if not blank.

This applies to both branches of `LineFields.init`, including when the model skipped the entry. The deterministic match beats the model because small models miss or invent tickets.

- [ ] **Step 1: Write failing tests** in `TicketDetectorTests.swift`:

```swift
@Test func findsFirstMatch() {
    #expect(TicketDetector.firstTicket(in: "Fixed login for ABC-123, then XY-9", pattern: #"[A-Z][A-Z0-9]+-\d+"#) == "ABC-123")
}
@Test func noMatchIsNil() {
    #expect(TicketDetector.firstTicket(in: "refactored the scheduler", pattern: #"[A-Z][A-Z0-9]+-\d+"#) == nil)
}
@Test func invalidPatternIsNil() {
    #expect(TicketDetector.firstTicket(in: "ABC-123", pattern: "[") == nil)
}
@Test func emptyPatternIsNil() {
    #expect(TicketDetector.firstTicket(in: "ABC-123", pattern: "") == nil)
}
```

Add these to `CompilerTests.swift`, using its existing stub-client helpers:
- `ticketDetectedFromTextWhenModelOmitsIt`: the entry has `ticketRef: nil` and text "Reviewed PROJ-42 rollout", and the model item has `"ticket": null`. Expect `line.ticket == "PROJ-42"`.
- `entryTicketBeatsDetectedAndModel`: `ticketRef: "AA-1"`, text contains "BB-2", the model says "CC-3". Expect `"AA-1"`.
- `detectedBeatsModel`: `ticketRef: nil`, text contains "BB-2", the model says "CC-3". Expect `"BB-2"`.
- `skippedEntryStillGetsDetectedTicket`: the model returns no item for the entry, whose text contains "BB-2". Expect `"BB-2"`.

In `EntrySnapshot` tests or `CompilerTests`, add `#expect(EntryType.ticket.displayName == "Ticket")`.

- [ ] **Step 2: Run** `swift test --package-path Packages/TimesheetCore`. Expect the new tests to FAIL (`TicketDetector` undefined).
- [ ] **Step 3: Implement.**
  - Use `try? Regex(pattern)` and `text.firstMatch(of:)`. Return the matched substring.
  - Change `displayName` for `.ticket` to `"Ticket"`.
  - `LineFields.init` gains a `ticketPattern: String` parameter. Pass it `settings.template.ticketPattern` from the compiler.
- [ ] **Step 4: Run the core tests.** All PASS.
- [ ] **Step 5: Commit** `feat: detect tickets in entry text and rename the Ticket type`.

---

### Task 2: Periods and day ranges

**Files:**
- Create: `Packages/TimesheetCore/Sources/TimesheetCore/Period/DayRange.swift`
- Create: `Packages/TimesheetCore/Sources/TimesheetCore/Period/Period.swift` (holds `PeriodKind` and `Period`)
- Test: `Packages/TimesheetCore/Tests/TimesheetCoreTests/PeriodTests.swift`

**Interfaces (Produces):**

```swift
public struct DayRange: Equatable, Sendable {
    public let start: Date   // start of day in `calendar`
    public let end: Date     // start of the last day (inclusive)
    /// Swaps the dates if `to` is before `from`.
    public init(from: Date, to: Date, calendar: Calendar = .current)
    /// Every day in the range, oldest first, as start-of-day dates.
    public func days(calendar: Calendar = .current) -> [Date]
    /// `DayKey.string(for:timeZone: calendar.timeZone)` for each day.
    public func keys(calendar: Calendar = .current) -> [String]
}

public enum PeriodKind: String, CaseIterable, Sendable {
    case day, week, month
    public var displayName: String  // "Day", "Week", "Month"
}

public enum Period {
    public static func range(_ kind: PeriodKind, containing anchor: Date, calendar: Calendar = .current) -> DayRange
    /// Moves the anchor by whole periods; month steps clamp (Jan 31 + 1 month = Feb 28/29).
    public static func shift(_ anchor: Date, by steps: Int, kind: PeriodKind, calendar: Calendar = .current) -> Date
    /// Day: medium date ("Oct 22, 2026"). Week: interval, medium dates ("Oct 19 – 25, 2026").
    /// Month: localized "MMMMyyyy" template ("October 2026").
    public static func label(_ kind: PeriodKind, anchor: Date, calendar: Calendar = .current, locale: Locale = .current) -> String
    /// Custom range label: medium-date interval; a one-day range reads like a Day label.
    public static func label(_ range: DayRange, calendar: Calendar = .current, locale: Locale = .current) -> String
}
```

Use `calendar.dateInterval(of: .weekOfYear / .month, for:)` for the week and month bounds. Use `DateIntervalFormatter` (`dateStyle = .medium`, `timeStyle = .none`) for the interval labels.

- [ ] **Step 1: Write failing tests.** Use a Gregorian calendar with `timeZone = TimeZone(identifier: "Europe/Berlin")!` and `locale = Locale(identifier: "en_US")`.
  - `dayRangeIsOneDay`: day around 2026-10-22 15:00 → `keys == ["2026-10-22"]`.
  - `weekMondayFirst`: `firstWeekday = 2`, anchor 2026-10-22 → keys from `"2026-10-19"` to `"2026-10-25"`, count 7.
  - `weekSundayFirst`: `firstWeekday = 1` → `"2026-10-18"` to `"2026-10-24"`.
  - `weekCrossesYear`: `firstWeekday = 2`, anchor 2026-12-31 → first `"2026-12-28"`, last `"2027-01-03"`.
  - `monthLeapFebruary`: anchor 2028-02-10 → 29 keys, first `"2028-02-01"`, last `"2028-02-29"`.
  - `rangeNormalizesReversedDates`: `DayRange(from: Oct 25, to: Oct 20)` → keys `"2026-10-20"`…`"2026-10-25"`.
  - `shiftMonthClamps`: shift 2028-01-31 by 1 month → key `"2028-02-29"`.
  - `shiftWeekBackwards`: shift 2026-10-22 by −1 week → `"2026-10-15"`.
  - `monthLabel`: `label(.month, anchor: 2026-10-22)` == `"October 2026"`.
  - `weekLabelMentionsBothEnds`: week label contains `"Oct"`, `"19"` and `"25"`.
- [ ] **Step 2: Run the core tests.** Expect FAIL (types undefined).
- [ ] **Step 3: Implement** `DayRange`, `PeriodKind` and `Period`.
- [ ] **Step 4: Run the core tests.** All PASS.
- [ ] **Step 5: Commit** `feat: add day, week and month periods and day ranges`.

---

### Task 3: Range queries, moving entries, multi-day render

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Persistence/Store.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Persistence/LogEntry.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Output/LineRenderer.swift`
- Test: `PersistenceTests.swift`, `LineRendererTests.swift`

**Interfaces:**
- Consumes: `DayRange.keys(calendar:)` (Task 2).
- Produces:

```swift
extension Store {
    /// Entries whose dayKey is in `range`, sorted by dayKey then createdAt.
    public static func entries(in range: DayRange, in context: ModelContext, calendar: Calendar = .current) throws -> [LogEntry]
    /// Saved results for days in `range`, sorted by dayKey.
    public static func compiled(in range: DayRange, in context: ModelContext, calendar: Calendar = .current) throws -> [CompiledDay]
}
extension LogEntry {
    /// Moves the entry to the calendar date of `day` in `timeZone`.
    public func move(to day: Date, timeZone: TimeZone = .current)
}
extension LineRenderer {
    /// Each day rendered with `render(_:day:template:)`, in the given order; days with no lines are skipped; joined by "\n".
    public static func render(days: [(day: Date, lines: [TimesheetLine])], template: TemplateSettings) -> String
}
```

Predicate: `let keys = range.keys(calendar:)`, then `#Predicate { keys.contains($0.dayKey) }`. Sort in a `FetchDescriptor` by `\.dayKey` then `\.createdAt`.

- [ ] **Step 1: Write failing tests.**
  - `entriesInRangeSortedByDayThenCreation`: insert entries on Oct 21, 22 (two, with set `createdAt`) and 26. The range is Oct 20–25. Expect texts in day, then creation order. Oct 26 is excluded.
  - `compiledInRangeSortedByDay`: CompiledDay for Oct 23 and Oct 21, plus Oct 30 outside the range. Expect keys `["2026-10-21","2026-10-23"]`.
  - `moveChangesDayKey`: `entry.move(to: Oct 24 at 23:30)` → `dayKey == "2026-10-24"`. `Store.entries(on: Oct 22)` no longer returns it.
  - `renderDaysJoinsInOrderSkippingEmpty` (in `LineRendererTests`): default template, two days with one line each and a middle day with `[]`. The output equals `render(day1) + "\n" + render(day3)` and contains no blank line.
- [ ] **Step 2: Run the core tests.** Expect FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the core tests.** All PASS.
- [ ] **Step 5: Commit** `feat: query entries and results by day range`.

---

### Task 4: App name, calendar picker and period bar

**Files:**
- Modify: `App/Info.plist`. Set `CFBundleName` to `Timesheet Assistant`. The menu bar and About panel read it. Leave `PRODUCT_NAME`, so the `.app` file name and `scripts/build-dmg.sh` don't change.
- Create: `App/Shared/CalendarButton.swift`
- Create: `App/Shared/PeriodBar.swift`
- Modify: `App/DailyLog/DailyLogView.swift`. Remove `DayBar`; Task 5 replaces its use.
- Modify: `App/Compile/CompileView.swift`. Use `PeriodBar` for now with kind fixed to `.day`; Task 6 widens it.
- Check `project.yml` sources include `App/` recursively, so the new `App/Shared` folder is picked up.

**Interfaces:**
- Consumes: `Period`, `PeriodKind`, `DayRange` (Task 2).
- Produces:

```swift
/// A button showing `title` that opens a popover with a graphical (month grid) DatePicker; picking a date sets `date` and closes the popover.
struct CalendarButton: View { init(title: String, date: Binding<Date>, accessibilityLabel: String) }

/// [◀] [CalendarButton(Period.label)] [▶] [Today]  …  [Day|Week|Month segmented]
/// Arrows call Period.shift by ±1 of `kind`. "Today" sets anchor = Date(), disabled when the current range already contains today.
struct PeriodBar: View { init(anchor: Binding<Date>, kind: Binding<PeriodKind>) }
```

Keep the existing accessibility labels and help text ("Previous day" etc.), worded per kind ("Previous week", "Next month").

- [ ] **Step 1: Implement** the views and the Info.plist change.
- [ ] **Step 2: Build** with the app build command. Expect `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** `feat: calendar date picker, period bar and spaced app name`.

---

### Task 5: Daily log by day, week or month

**Files:**
- Modify: `App/RootView.swift`
- Modify: `App/DailyLog/DailyLogView.swift`
- Modify: `App/DailyLog/EntryEditor.swift`

**Interfaces:**
- Consumes: `PeriodBar` (Task 4), `Period.range`, `DayRange.keys`, `LogEntry.move(to:)` (Task 3), `TicketDetector.firstTicket` (Task 1).

**Behavior:**
- **`RootView` state.** It keeps one shared `@State anchor: Date`, which replaces `day`. `followToday()` keeps working on `anchor`. It also has `@AppStorage("logPeriod") logPeriod: PeriodKind`, which defaults to `.day`.
- **`DailyLogView(anchor:kind:)`** shows the `PeriodBar`, then an entry list for `Period.range(kind, containing: anchor)`. The list is rebuilt with `.id` per range keys and kind.
- **The entry list** uses `@Query` on `keys.contains($0.dayKey)`, sorted by dayKey then createdAt.
  - In Day mode, it shows a flat list, as today.
  - In Week and Month mode, it shows a `Section` per day that has entries. Headers use the full date, for example "Thursday, Oct 22". Empty days are hidden.
  - The empty state text is "No entries this week" or "No entries this month". Day mode keeps today's text.
- **New entry (⌘N).** It defaults to the anchor day if the anchor is in range, or else the first day of the range.
- **`EntryEditor`** gains a Day row: a `CalendarButton` with the medium date. Saving a new entry uses that day. Saving an edit with a changed day calls `entry.move(to:)`. Replace `init(day:entry:)` with `init(defaultDay: Date, entry: LogEntry?)`; an existing entry's day is parsed from its `dayKey`.
- **Ticket field prompt.** When the field is blank and `TicketDetector.firstTicket(in: text, pattern: settings.template.ticketPattern)` finds a match, the prompt reads "Found in text: ABC-123". Otherwise it reads "e.g. ABC-123". Read the settings via `@EnvironmentObject SettingsStore`.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Build.** Expect `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** `feat: view the daily log by day, week or month`.

---

### Task 6: Compile a day, week, month or custom range

**Files:**
- Modify: `App/RootView.swift`
- Modify: `App/Compile/CompileView.swift`
- Modify: `App/Compile/CompileViewModel.swift`

**Interfaces:**
- Consumes: `PeriodBar`, `CalendarButton` (Task 4), `DayRange`, `Period` (Task 2), `Store.entries(in:)`, `Store.compiled(in:)`, `LineRenderer.render(days:template:)` (Task 3).

**Behavior and decisions:**
- **Range choice.** Add `enum CompileRangeKind: String, CaseIterable { case day, week, month, custom }` in `CompileView.swift`, stored as `@AppStorage("compileRange")` in `RootView`, default `.day`.
  - The bar is a segmented control with Day, Week, Month and Custom.
  - In Day, Week and Month mode, the bar is the `PeriodBar` behavior on the shared anchor.
  - In Custom mode, it shows "From" and "To" `CalendarButton`s, with `@State customStart` and `customEnd` in `RootView`, both defaulting to today. The range is `DayRange(from:to:)`.
- **`CompileViewModel(range: DayRange, …)`** replaces `init(day:)`. A single day is a one-day range. It holds:

  ```swift
  struct DayResult { let day: Date; var entryIds: [UUID]; var lines: [TimesheetLine]; var issues: [LineIssue]; var hasSaved: Bool }
  struct DatedLine: Identifiable { let day: Date; let line: TimesheetLine; var id: UUID { line.id } }
  @Published private(set) var days: [DayResult]     // only days in range that have entries or a saved result
  var lines: [DatedLine]                            // flattened, day order then start
  ```

  - `load()` uses the range queries.
  - `revalidate()` validates each day separately against that day's `entryIds`.
  - `edit` and `delete` find the owning day by line id, then save only that day's `CompiledDay`.
- **Compile.**
  - It runs the days that have entries one at a time, oldest first, each with its own `Compiler.compile(entries:day:settings:)` call. Each day is saved as soon as it finishes.
  - State becomes `.running(done: Int, total: Int)`. The bar shows "Compiling day 2 of 5…" for ranges and "Compiling…" for one day.
  - Cancel stops after the current call. Days already saved stay saved.
  - If a day fails, stop. State becomes `.failed("<medium date>: <message>")`.
  - "Replace the saved result…" confirmation: shown when any day to compile has a saved result. For ranges it reads "Replace saved results for N days?".
- **Table.** Add a "Date" column first, after the warning icon. It shows the template-independent short date, for example "Oct 22", and only in multi-day ranges. Row warnings come from that row's day issues.
- **Footer total.** The sum of all lines, against `workingMinutes × (number of days with entries)`.
- **Copy button.** The label is "Copy day" for one day and "Copy range" otherwise. Preview and copy use `LineRenderer.render(days:)`.
- **Empty text.** "No entries for this day" or "No entries in this range". The overlay reads "Compile the range to get timesheet lines." for ranges.
- **Missing-lines summary.** Uses the union of all days' issues.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Build.** Expect `** BUILD SUCCEEDED **`. Run the core tests too: all PASS.
- [ ] **Step 3: Commit** `feat: compile a week, month or custom range`.
