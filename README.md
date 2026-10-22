# Timesheet Assistant

A native macOS app that turns your daily work notes into timesheet lines with a local LLM.

You log private notes through the day: ticket summaries, notes, pull request descriptions, meeting notes. At the end of the day the app compiles them into plain-text lines in your company's timesheet format. You review and edit them, then copy and paste them into your timesheet system.

Your notes never leave your Mac. The only exception is a custom endpoint that you configure yourself.

## Features

- **Daily log.** Add, edit and delete entries per day. Each entry has a type, an optional ticket reference, an optional duration hint (for example `~2h`) and free text.
- **Configurable template.** Field order, separator, date and time formats, empty-ticket placeholder, ticket pattern, and an optional description length limit.
- **Your own lists.** Activity types and classifications are lists you define. The model must pick from them, and any other value is flagged.
- **Working hours.** Set start, end, lunch and rounding. Tasks are spread across the working window with no gaps or overlaps. Duration hints are honoured, and stated meeting times keep their slot.
- **Compile.**
  - Run the compile and edit the resulting lines in a table. Problems are flagged inline.
  - A live plain-text preview updates as you edit, and **Copy day** (⌘⇧C) copies it.
  - Each day's result is saved. Re-compiling asks before replacing it.
- **On-device models (MLX).**
  - Download models from Settings › Models while the app runs. Weights are never bundled with the app.
  - The list depends on your Mac's RAM:

    | RAM | Models |
    |-----|--------|
    | 16 GB | Qwen3 4B, Llama 3.2 3B Instruct, Gemma 4 E4B |
    | 32 GB | All of the above, plus Qwen3 8B, Qwen3 14B and Gemma 3 12B |

- **Custom endpoint.**
  - Any OpenAI-compatible server works, for example Ollama, LM Studio or llama.cpp server.
  - Localhost and LAN addresses are accepted silently. Any other host needs https and an explicit confirmation that your data will leave the Mac.

## Privacy

- **Local storage.** Entries, results and settings are stored under `~/Library/Application Support/TimesheetAssistance/`.
- **No sync or tracking.** iCloud/CloudKit sync is disabled, and there is no analytics or telemetry.
- **Limited network use.** The app only talks to:
  - Hugging Face, when you download a model;
  - the endpoint you configure.
- **Redirects refused.** The endpoint client refuses redirects, so your data can't be forwarded to an unconfirmed host.
- **API key.** The key is stored in the Keychain and is only sent to the host it was saved for.

## Requirements

- Apple Silicon Mac running macOS 15 or later.
- To build:
  - Xcode 27 or later, with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).
  - [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build and run

```bash
xcodegen generate
xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build
```

You can also open `TimesheetAssistant.xcodeproj` in Xcode and run it. The project file is generated, so it is not committed.

## Tests

```bash
# Core logic: settings, rendering, scheduling, validation, prompt/parse, endpoint client, persistence
swift test --package-path Packages/TimesheetCore

# On-device model download and client (needs Metal, so run it through xcodebuild)
cd Packages/LocalModels && xcodebuild test -scheme LocalModels -destination 'platform=macOS'
```

## Project layout

```
App/                      SwiftUI app (Daily log, Compile, Settings)
Packages/TimesheetCore/   UI-free logic and its tests
Packages/LocalModels/     MLX on-device models (download, load, generate)
Design/AppIcon.svg        Icon source; scripts/render-icon.swift renders the asset catalog
docs/superpowers/         Design spec and implementation plan
project.yml               XcodeGen project definition
```

## License

MIT. See [LICENSE](LICENSE).
