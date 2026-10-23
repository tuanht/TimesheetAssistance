# Fixed Times Guard and System Prompt Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop invented meeting times from pinning entries across lunch, and let the user override the compile system prompt from a new Developer settings tab.

**Architecture:** A new pure `ClockMention` finds clock times written in entry text. `Compiler` keeps a model's `fixedStart`/`fixedEnd` only when the start is one of those times; `ResponseSchema` forces both to `null` for entries without any; the prompt rule is sharpened. `AppSettings` gains an optional system prompt override that `PromptBuilder` uses instead of its built-in text, edited in a new Developer tab.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md` (Compile pipeline; Settings)

## Global Constraints

- Flag, don't fix silently: a real stated meeting that crosses lunch keeps its slot and is flagged `.inLunch` by `LineValidator`. Only times the text never states are dropped.
- Settings decoding stays forward-compatible: new fields use `decodeIfPresent` with defaults.
- `ResponseSchema` output stays byte-stable in property order (`key` first); constrained decoders depend on it.
- One responsibility per file; core logic is TDD in TimesheetCore, the app tab stays thin.

## Decisions

- **Mentions recognised:** `H:mm` / `HH:mm` (hour 0–23, minutes 00–59), and `Ham`/`Hpm`/`H:mmam`/`H:mm pm` (hour 1–12, case-insensitive, optional space before am/pm; 12am = 00:00, 12pm = 12:00). Not recognised: `9.30`, `14h30` (clash with durations like `1h30` and version numbers). A digit or `:` directly before or after the match blocks it (so `1:2:3`, `112:30` do not match).
- **Guard:** keep `fixed` only if the parsed `fixedStart` is in `ClockMention.times(in: entry.text)`. The end is trusted once the start matches (it may be derived from a stated length). `contextSummary` and `durationHint` are not searched.
- **Schema:** an entry whose text has no clock mention gets `{"type":"null"}` for `fixedStart` and `fixedEnd`; others keep `anyOf string|null`.
- **Prompt rule:** `- "fixedStart" and "fixedEnd": "HH:mm" in 24-hour time, set only when the entry text states a clock time such as 09:30 or 2pm; otherwise null. A duration such as 2h or 45 min is not a clock time.`
- **Override:** `AppSettings.systemPromptOverride: String?`, default `nil`. `PromptBuilder` uses it when it is non-blank after trimming; otherwise `PromptBuilder.system`. The ticket-summary prompt is not affected.
- **Developer tab:** label "Developer", SF Symbol `hammer`, tag `"developer"`, last tab. A monospaced `TextEditor` starts with the override or, if none, `PromptBuilder.system`. Every edit saves through `session.update`; text that is blank or equal to `PromptBuilder.system` (after trimming) is stored as `nil`. A "Reset to default" button (disabled when no override) sets `nil` and reloads the default text. A footer: "Replaces the built-in instructions sent with every compile. Entries, lists and the reply schema are still added automatically."

## Review Focus

- An entry "Standup 9:30, 15 min" with model `09:30–09:45` keeps its fixed slot.
- "Worked 7h on ABC-1" with model `08:00–16:00` becomes flexible and is split at lunch.
- "Workshop 11:00-14:00" stays fixed and is flagged `.inLunch`.
- Model returns `"2pm"`-style start for text "call at 2pm": `ClockTime("2pm")` fails to parse, so fixed is dropped (acceptable; the schema and prompt ask for HH:mm).
- A settings file without `systemPromptOverride` loads with `nil`.

---

### Task 1: ClockMention and the Compiler guard

**Files:**
- Create: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/ClockMention.swift`
- Create: `Packages/TimesheetCore/Tests/TimesheetCoreTests/ClockMentionTests.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/Compiler.swift` (`LineFields.init`)
- Modify: the existing Compiler tests file (add guard tests)

**Interfaces:**
- Produces: `public enum ClockMention { public static func times(in text: String) -> Set<ClockTime> }` (`ClockTime` must be `Hashable`; add the conformance if missing).

- [ ] **Step 1: Failing tests** for `ClockMention.times(in:)`:
  - `"Standup 9:30"` → `{09:30}`; `"Workshop 11:00-14:00"` → `{11:00, 14:00}`; `"call at 2pm"` → `{14:00}`; `"12am"` → `{00:00}`; `"12pm"` → `{12:00}`; `"9:15 AM"` → `{09:15}`.
  - Empty: `"Worked 7h on ABC-1"`, `"1h30 review"`, `"v1.2.3"`, `"9.30"`, `"25:00"`, `"9:60"`, `"13pm"`, `"112:30"`.
- [ ] **Step 2: Failing Compiler tests** with a stub client:
  - text `"Worked 7h on ABC-1"`, model `fixedStart "08:00"`, `fixedEnd "16:00"`, default working hours → lines split around 12:00–13:00, no `.inLunch` issue.
  - text `"Standup 9:30"`, model `09:30`–`09:45` → one line 09:30–09:45.
  - text `"Workshop 11:00-14:00"`, model `11:00`–`14:00` → one line 11:00–14:00 and an `.inLunch` issue.
- [ ] **Step 3: Run** `swift test --package-path Packages/TimesheetCore`. Expected: new tests fail.
- [ ] **Step 4: Implement** `ClockMention` and the guard in `LineFields.init`.
- [ ] **Step 5: Run** the core suite. Expected: all pass.
- [ ] **Step 6: Commit** `fix(compile): drop model meeting times the entry text never states`.

### Task 2: Per-entry schema and prompt rule

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/ResponseSchema.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/PromptBuilder.swift`
- Modify: existing ResponseSchema and PromptBuilder tests

**Interfaces:**
- Consumes: `ClockMention.times(in:)` (Task 1).
- Produces: `ResponseSchema.json(keys: [String], timedKeys: Set<String>, activityTypes: [String], classifications: [String]) -> String`.

- [ ] **Step 1: Failing tests:** for a key not in `timedKeys`, `prefixItems[i].properties.fixedStart` and `fixedEnd` equal `{"type":"null"}`; for a timed key they keep `anyOf` string/null. `PromptBuilder.build` passes `e1` as timed for text `"Standup 9:30"` and not for `"Worked 7h"`. `PromptBuilder.system` contains `A duration such as 2h or 45 min is not a clock time.`
- [ ] **Step 2: Run** core tests. Expected: new tests fail.
- [ ] **Step 3: Implement**; update every `ResponseSchema.json` call site.
- [ ] **Step 4: Run** the core suite and the LocalModels suite (`cd Packages/LocalModels && xcodebuild test -scheme LocalModels -destination 'platform=macOS'`, in case it builds schemas). Expected: all pass.
- [ ] **Step 5: Commit** `feat(compile): forbid meeting times for entries that state none`.

### Task 3: System prompt override and Developer tab

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Settings/AppSettings.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/PromptBuilder.swift`
- Create: `App/Settings/DeveloperTab.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: AppSettings and PromptBuilder tests; `CLAUDE.md` (mention the Developer tab and override in Architecture/Compile step 1)

**Interfaces:**
- Produces: `AppSettings.systemPromptOverride: String?` (init parameter with default `nil`, last position); `PromptBuilder.system` stays `static let` and public.

- [ ] **Step 1: Failing tests:** decoding JSON without the key gives `nil`; round-trip keeps a value; `PromptBuilder.build` uses the override as `system` when set, and the built-in when the override is `nil`, `""` or `"  \n"`.
- [ ] **Step 2: Run** core tests. Expected: new tests fail.
- [ ] **Step 3: Implement** core, then `DeveloperTab` per Decisions, and add it to `SettingsView`.
- [ ] **Step 4: Run** the core suite, then `xcodegen generate && xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build`. Expected: pass, build succeeds.
- [ ] **Step 5: Commit** `feat(settings): Developer tab to override the compile system prompt`.
