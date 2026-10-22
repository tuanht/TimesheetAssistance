# Top-center tabs and per-line copy buttons

Small UI change agreed in chat on 2026-10-22. No separate spec: this plan is the description the user approved. The project spec (`docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md`) and `CLAUDE.md` still bind.

## Global Constraints

- App layer only (`App/`). No TimesheetCore changes; app views stay thin.
- macOS 15+, SwiftUI. Match surrounding code style: doc comments on types, short `///` WHY comments, no narration comments.
- User-facing text: plain English, short.
- Rename is user-facing only: "Daily log" becomes "Log". Code names (`DailyLogView`, `App/DailyLog/` folder) stay.
- Verify with the app build:
  `xcodegen generate && xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build`
- Core tests must still pass: `swift test --package-path Packages/TimesheetCore`.

## Task 1: Top-center tabs replace the sidebar

Files: `App/RootView.swift`, `App/DailyLog/DailyLogView.swift`.

- Remove `NavigationSplitView` and the sidebar `List` from `RootView`. The detail content (switch on the selected section) becomes the window's root content.
- Section names: `case log = "Log"` and `case compile = "Compile"` (rename the `dailyLog` case to `log`).
- Selection is non-optional and remembered across launches: `@AppStorage("mainTab") private var selection: Section = .log` (make `Section` `String`-backed so `@AppStorage` works). Drop the `case nil` branch.
- Put a segmented `Picker` over `Section.allCases` in the window toolbar with `ToolbarItem(placement: .principal)`, labels hidden, so it sits top-center.
- Keyboard shortcuts: ⌘1 selects Log, ⌘2 selects Compile. Add them as menu commands (e.g. a `CommandGroup` or `CommandMenu`) or as hidden toolbar buttons — implementer's choice, but they must work while either tab is showing and must not clash with existing shortcuts (⌘N new entry, ⌘⇧C copy).
- Keep everything else on `RootView` unchanged: `.frame(minWidth: 720, minHeight: 440)`, the day-change `onReceive`, `scenePhase` handling, `anchor`, `logPeriod`, `compileRange`, `customStart`, `customEnd`.
- `DailyLogView`: change `.navigationTitle("Daily log")` to `.navigationTitle("Log")`. Leave its existing toolbar buttons (New / Edit / Delete) as they are; they stay at the trailing side.
- Without `NavigationSplitView`, make sure the window still shows a toolbar so the principal picker and Daily log buttons appear (a toolbar with items is enough; check in the built app if possible).

Acceptance: app builds; window has no sidebar; "Log | Compile" segmented control is centered in the toolbar; choice survives relaunch; ⌘1/⌘2 switch tabs; window title reads "Log" or "Compile".

## Task 2: Copy buttons on Description and Ticket cells

File: `App/Compile/CompileView.swift`.

- In `LinesTable`, the Description and Ticket cells each get a small trailing icon button (`doc.on.doc`, `.buttonStyle(.borderless)`, secondary foreground) that copies the cell's text to `NSPasteboard.general` as `.string`.
- It copies exactly what the field shows now, including typing not yet committed. The cleanest place is inside `CommitField`, which owns the live `text`: add an opt-in (e.g. `var copyable = false` or an optional copy label) that adds the button after the `TextField` in an `HStack`. Time fields don't get it.
- Feedback: after a click the icon switches to `checkmark` for about 1.5 s, then back. Use a token pattern like `CompileDayView.copy()` so rapid clicks don't flicker early.
- Disabled when the text is empty (so a line with no ticket has a disabled Ticket copy button).
- `.help` text: "Copy description" / "Copy ticket". Accessibility label the same.
- Copying must not commit, change, or revalidate the line.

Acceptance: app builds; each compiled line shows the two buttons; clicking copies the shown text; empty ticket disables its button; checkmark feedback shows then reverts.
