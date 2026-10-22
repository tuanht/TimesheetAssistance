# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A native macOS SwiftUI app (Apple Silicon, macOS 15+). It compiles private daily work notes into plain-text timesheet lines, using either a local LLM through MLX or a user-configured OpenAI-compatible endpoint.

- **Design spec (binding):** `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md`
- **Implementation plan:** `docs/superpowers/plans/2026-10-22-timesheet-assistant.md`

## Commands

```bash
# Core tests (fast; run these after any core change)
swift test --package-path Packages/TimesheetCore

# Integrations tests (MCP client)
swift test --package-path Packages/Integrations

# LocalModels tests (need Metal shaders, so run through xcodebuild)
cd Packages/LocalModels && xcodebuild test -scheme LocalModels -destination 'platform=macOS'

# App build (the .xcodeproj is generated from project.yml and git-ignored)
xcodegen generate && xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build

# Re-render the app icon after editing Design/AppIcon.svg
swift scripts/render-icon.swift

# Release DMG (ad-hoc signed unless SIGN_IDENTITY is set) -> build/TimesheetAssistant-<version>.dmg
./scripts/build-dmg.sh
```

- **Metal Toolchain.** Building needs it: `xcodebuild -downloadComponent MetalToolchain`.
- **Testing.** Tests use Swift Testing (`import Testing`), not XCTest.

## Architecture

- **`Packages/TimesheetCore`** holds all logic, with no UI. One folder per job (`Settings/`, `Output/`, `Schedule/`, `Validate/`, `Compile/`, `LLM/`, `Catalog/`, `Persistence/`, `Review/`, `Period/`).
- **`Packages/LocalModels`** wraps `mlx-swift-lm` (pinned to exact 3.32.3):
  - `MLXModelManager` handles download, delete and `isDownloaded`, and keeps at most one model loaded.
  - `MLXClient` conforms to `LLMClient`.
  - `HubDownloader` is our own minimal Hugging Face downloader. It stages each download and moves it into place only when every file has arrived.
- **`Packages/Integrations`** holds the read-only MCP client (`MCPClient`, Streamable HTTP) for Jira and GitHub context. It depends on TimesheetCore only.
- **`App/`** is a thin SwiftUI layer: `DailyLog/`, `Compile/` and `Settings/`.
  - One `SettingsSession` / `SettingsStore` is injected into both the main window and the Settings scene.
  - The Settings tab is selected with `@AppStorage("settingsTab")`.

### Compile pipeline

1. **Prompt.** `PromptBuilder` builds the prompt. Entries get short keys (`e1`, `e2`, …) and their text is wrapped in `<entry>` delimiters.
2. **Model.** The LLM returns JSON: per entry, a relative effort in `minutes`, any stated time, a description, a ticket, an activity type and a classification.
3. **Parse.** `ResponseParser` strips `<think>` blocks and code fences, then decodes leniently. A missing or null field becomes empty so the validator can flag it; one bad item doesn't fail the whole reply.
4. **Schedule.** `Scheduler`, not the model, places entries on the clock:
   - Fixed meeting times keep their slot, and hints get their exact minutes.
   - The rest of the day is shared by largest-remainder allocation on the rounding grid, so the total is exact and size order holds.
   - An entry that crosses lunch or a meeting is split into several lines.
5. **Validate.** `LineValidator` only flags problems and never changes lines. `LineRenderer` produces the output: lines only, with no header or markdown.

## Rules that must hold

These come from the spec and from review rulings. Don't regress them.

- **Privacy:**
  - No network calls except user-initiated Hugging Face downloads, the configured endpoint, the Atlassian and GitHub MCP hosts (`MCPServer.atlassian`, `MCPServer.github`) and their OAuth traffic. No telemetry.
  - Only reference identifiers (`ABC-123`, `owner/repo#45`) go to Atlassian and GitHub. Entry text, notes and summaries never do.
  - Only allow-listed read tools (`MCPServer.allowedTools`) may be called. Anything else throws before any request.
  - A credential is attached only to a request whose host equals its service's MCP host.
  - Keep `cloudKitDatabase: .none`.
  - The endpoint client and the MCP client refuse redirects.
- **Remote endpoints:** they need https and `remoteConfirmed`. `ClientPlan` refuses an unconfirmed non-local endpoint.
- **API key:** the stored key is only sent to the saved endpoint's host. Credentials in URLs are rejected.
- **Model weights:** download them at runtime only. Never bundle them in the `.app` or a DMG.
- **Flag, don't fix silently:**
  - Never truncate a description.
  - Invalid values (lists, ticket pattern, times, empty description, orphan lines) are flagged for the user.
- **Days** are matched by `DayKey` (`yyyy-MM-dd`), never by a `Date` instant.
- **Times:** `ClockTime` decodes 00:00–47:59 so overflow lines survive a reload.
- **Settings decoding** is forward-compatible (`decodeIfPresent` with defaults). An unreadable file is backed up with a timestamp, and the user is told.
- **Separators:** only an empty separator is invalid. The substitute must not contain the separator or its trimmed core.

## Conventions

- **Testing:** TDD for core logic. Keep UI-independent logic in TimesheetCore with tests; app views stay thin.
- **Code size:** one responsibility per file, and prefer small pure functions.
- **User-facing error text:** plain English, short, actionable. Never include API keys, request bodies or raw model output.
- **Agent workflow:**
  - Subagents run on Opus.
  - Don't use the `tuanht:orchestrate` skill.
