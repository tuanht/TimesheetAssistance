# Timesheet Assistant — Design

Date: 2026-10-22
Status: Approved 2026-10-22

## Intent

A native macOS app where the user logs private work info through the day (ticket/task summaries, notes, pull request descriptions, meeting notes). At the end of the day the app compiles those entries into timesheet lines in the company's plain-text format, using an LLM that runs locally. The user edits the result and copy/pastes it into the company timesheet system.

Why: writing the daily timesheet by hand from scattered notes is tedious. The raw notes are private and must not leave the Mac, so cloud LLMs are out.

## Goals

- Fast daily logging of free-text entries, grouped by date.
- Configurable timesheet template matching the company format.
- One-click compile of a day's entries into timesheet lines.
- Model spreads tasks across configured working hours; user edits times afterwards.
- Copy the whole day's result as plain text.
- On-device models, offered according to the Mac's RAM (16 GB / 32 GB tiers), downloadable in-app.
- Option to use a custom OpenAI-compatible endpoint (Ollama, LM Studio, llama.cpp server, etc.) instead of an on-device model.

## Non-goals

- No direct integration with the timesheet system (no API push). Output is copy/paste.
- No import from Jira, GitHub, calendar, or other tools in v1. Entries are typed or pasted by the user. Superseded by `2026-10-22-ticket-context-design.md`.
- No sync, accounts, or multi-device support.
- No cloud LLM providers.

## Anti-goals (failure even if it technically works)

- Any private entry data leaving the Mac, except to a custom endpoint the user explicitly configured.
- Telemetry, analytics, or crash reporting that sends data off the machine.
- The model inventing activity types or classifications outside the user's configured lists.
- Output that doesn't paste cleanly into the timesheet system (stray markdown, commentary, extra lines).

## Constraints

- macOS native app, SwiftUI. Apple Silicon only (MLX requirement).
- Development machine: macOS 27, Xcode 27.1, 16 GB RAM, `xcodegen` installed.
- All data stored locally under `~/Library/Application Support/TimesheetAssistance/`.
- Model weights stored locally under Application Support. Downloaded at runtime only; never bundled in the `.app` or a DMG build (user decision).

## Decided by the user

### Entries
- Types: ticket/task summary, notes, pull request description, meeting notes.
- Entered daily, stored locally.

### Timesheet template
- Plain text. One line per work block.
- Fields: date, start time, end time, description, ticket/task reference, activity type, classification.
- Result is copy/pasted into the company timesheet system.

### Grouping
- One timesheet line per entry. Entries are never merged, even when they share a ticket.

### Activity type and classification
- Two independent lists, both configurable by the user in Settings. No mapping between them or to tickets.

### Real example
- The user cannot share a real timesheet line. The format below is inferred from the field list, so every formatting choice must be configurable rather than hard-coded.

### Time allocation
- The model spreads the day's tasks across the configured working hours.
- The user can edit start/end times after compile.

### Models
- On-device model choices depend on RAM (16 GB vs 32 GB).
- 16 GB tier must include Gemma 4 (E4B, 4-bit: `mlx-community/gemma-4-e4b-it-4bit`).
- Custom endpoint for a model on a local server must be configurable.

## Builder's calls (made by Claude, user can override)

### Stack
- SwiftUI + SwiftData for storage. Xcode project generated with `xcodegen` (`project.yml` checked in).
- On-device inference: MLX Swift (`mlx-swift-lm` / `MLXLLM`) with Hugging Face downloads.
- Custom endpoint: OpenAI-compatible `/v1/chat/completions` client (base URL, model name, optional API key stored in Keychain).
- Minimum macOS: 15.

### Model catalog
| Tier | Model | Approx. size |
|------|-------|--------------|
| 16 GB | Qwen3 4B 4-bit | ~2.5 GB |
| 16 GB | Llama 3.2 3B Instruct 4-bit | ~2 GB |
| 16 GB | Gemma 4 E4B 4-bit | ~3 GB |
| 32 GB | Qwen3 8B 4-bit | ~5 GB |
| 32 GB | Qwen3 14B 4-bit | ~8 GB |
| 32 GB | Gemma 3 12B 4-bit | ~7 GB |

- 32 GB Macs see both tiers. 16 GB Macs see only the 16 GB tier, with the larger models hidden (or shown disabled with a "needs 32 GB" note).
- Catalog is a static list in code, easy to extend.
- **Known risk:** Gemma 4 MLX conversions target Python `mlx-vlm` / `mlx-lm`. MLX Swift support is unverified. Verify early. If unsupported, show Gemma 4 as "use via custom endpoint (Ollama / LM Studio)" until support lands.

### Template config
- Field order and separator are configurable (default separator ` | `).
- Date format and time format configurable (defaults `yyyy-MM-dd`, `HH:mm`).
- Activity type and classification are user-defined lists. The model must pick from them. Output is validated; invalid values are flagged for the user to fix, not silently accepted.
- Empty ticket ref renders as a configurable placeholder (default `—`).
- Optional max description length (default off). Over-length descriptions are flagged, not truncated silently.
- If the separator appears inside a description, it is replaced with a configurable substitute (default `/`).
- Output is the lines only: no header, no total line, no markdown.
- A single template in v1 (multiple templates can come later).

### Working hours
- Settings: working hours (default 09:00–17:30), lunch break (default 12:00–13:00), rounding (default 15 min).
- Compile fills the working window minus lunch with no gaps or overlaps. Bigger items get more time.
- If a meeting note mentions a time, the model keeps that slot.
- After edits, the app shows the day's total against working hours. It does not auto-shift neighbouring lines.

### Compile pipeline
1. Gather the day's entries.
2. Build a prompt: template fields, allowed activity types and classifications, working window, entries.
3. Ask the model for structured JSON, not free text. Exactly one item per entry. The model gives each entry an effort estimate, any time the entry text states, description, ticket, activity type and classification. The on-device model's decoding is constrained to the reply schema when possible, falls back to unconstrained decoding if that fails, and its reply is still parsed and validated like the endpoint's, which is never constrained. Deterministic code then lays the entries onto the clock (user-approved 2026-10-22: small models are unreliable at schedule arithmetic). An entry that crosses lunch is split into two lines for the same entry (user-approved 2026-10-22).
4. Parse and validate (one line per entry, times inside window, no overlaps, values in allowed lists, ticket format). Repair what can be repaired in code (rounding, sorting); flag the rest.
5. Render to plain text with the template.
6. Show an editable table; the plain-text preview updates live; "Copy day" copies it.

- Ticket refs: the model extracts them from entries; a configurable regex (default `[A-Z][A-Z0-9]+-\d+`) is used to validate.
- Compiled results are saved per day so reopening a day shows the last result. Re-compile overwrites after confirmation.

### Screens
1. **Daily log** — date picker, list of entries, add/edit/delete entry (type, optional ticket ref, free text).
2. **Compile** — pick a day, run, edit table, live plain-text preview, copy.
3. **Settings** — tabs: Template, Lists (activity/classification), Working hours, Models.
   - **Models tab** (user decision): models are downloaded directly from Settings while the app runs. No weights are bundled with the app. Shows RAM, catalog for the tier, download with progress, delete, select active. Custom endpoint config with "Test connection" lives here too.
   - Until a model is downloaded or an endpoint is configured, Compile is disabled with a link to the Models tab.

### Entry effort hint
- Each entry has an optional duration hint (e.g. "~2h", "30m"). The model honours hints first, then splits the rest of the window by its own judgement of size.

### App icon
- The user asked for an icon and left the design to the builder.
- Concept: a white note page with three short text lines, and a small clock badge overlapping its lower-right corner. Background is a macOS-style rounded square with a deep-teal-to-indigo gradient. Reads as "notes become timed entries".
- No text or letters in the icon. It must still read at 16×16.
- Authored as one SVG source in the repo (`Design/AppIcon.svg`). A script renders all `AppIcon.appiconset` sizes (16–1024 px, @1x/@2x) into the asset catalog.

### Privacy
Superseded by `2026-10-22-ticket-context-design.md`.

- No network calls except: Hugging Face model downloads (user-initiated) and the user's custom endpoint.
- No analytics or third-party SDKs that phone home.
- Custom endpoint: localhost and private LAN addresses are accepted silently. Any other host is allowed only after a clear warning that entry data will leave the Mac, which the user must confirm.

### Distribution
- v1 is a local build, signed for local run or Developer ID. Not sandboxed, not targeting the Mac App Store. Data and model weights live under `~/Library/Application Support/TimesheetAssistance/`.
- Keep entitlements minimal (outgoing network) so sandboxing can be added later.

## Left to the builder

- Exact UI layout and navigation (sidebar vs tabs).
- Prompt wording and JSON schema details.
- Download/caching mechanics for model weights.
- Test strategy (unit tests for template rendering, validation, time repair, and the endpoint client are expected).

## Build order

1. Project skeleton (`xcodegen`), SwiftData models, app icon.
2. Daily log UI.
3. Settings: template, lists, working hours.
4. Custom endpoint client and compile pipeline (fastest path to a working compile).
5. MLX on-device models: catalog, download, run. Verify Gemma 4 support.
6. Compile UI polish, copy, saved results.
