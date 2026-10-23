# Strict JSON for the Local Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When compiling with the on-device MLX model, force the reply to be JSON that matches the compile schema exactly. That covers one item per entry key, in order. It also limits `activityType` and `classification` to the Settings lists.

**Architecture:** `TimesheetCore` builds a JSON Schema string next to the prompt (`ResponseSchema`). It passes the schema through a new `LLMClient.complete(system:user:jsonSchema:)` overload. Clients that can't constrain decoding ignore it through a protocol-extension default. `MLXClient` compiles the schema with `MLXGuidedGeneration` (xgrammar, already in the pinned mlx-swift-lm 3.32.3) and generates with `GuidedGenerationLoop.run`, which masks logits so only schema-valid tokens can be sampled. `ResponseParser` and `LineValidator` stay unchanged, as a safety net.

**Tech Stack:** Swift 6, Swift Testing, mlx-swift-lm 3.32.3 (`MLXGuidedGeneration`, `MLXLMCommon`).

**Spec:** `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md` (binding), plus these decisions made in chat:
- The constraint applies to the local MLX model only.
- The OpenAI-compatible endpoint request is unchanged.
- Enum values come from Settings.

## Global Constraints

- **Platform:** macOS 15+, Apple Silicon. `mlx-swift-lm` stays pinned `exact: "3.32.3"`, and no new package dependencies are added. `MLXGuidedGeneration` is a product of the existing package.
- **Privacy:** no new network calls. Schema building and grammar compile are local only.
- **Flag, don't fix silently:**
  - The parser stays lenient.
  - The validator still flags bad values.
  - Never truncate a description.
- **Error text:** any new user-facing error text is plain English, short and actionable. It never includes model output or request bodies.
- **Tests:** use Swift Testing (`import Testing`), with TDD for core logic.
- **Code size:** one responsibility per file.
- **Commands:**
  - Core tests: `swift test --package-path Packages/TimesheetCore`.
  - LocalModels tests: `cd Packages/LocalModels && xcodebuild test -scheme LocalModels -destination 'platform=macOS'`.

## Review Focus

1. **Settings values with quotes, backslashes, unicode or duplicates.** The schema must still be valid JSON, so build it with `JSONSerialization` and never with string interpolation. Pinned by `schemaEscapesAndDedupesValues` (Task 1).
2. **An empty activityType or classification list.** An empty `enum` is unsatisfiable, so that field must fall back to a plain `string`. Pinned by `emptyListFallsBackToString` (Task 1).
3. **Many entries, so the reply exceeds `maxTokens`.** The user must get `LLMError.incompleteResponse` with its message, not a crash or a raw library error. Pinned by `guidedErrorsMapToIncompleteResponse` (Task 3).
4. **A model whose tokenizer xgrammar can't use.** Compile must still work, falling back to unconstrained generation. Pinned by `setupFailureFallsBack` (Task 3).
5. **Remote endpoint unaffected.** The body sent by `OpenAICompatibleClient` must not change. Pinned by `compilerPassesSchemaToClient` plus the unchanged `OpenAICompatibleClientTests` (Task 2).

---

### Task 1: Response schema in TimesheetCore

**Files:**
- Create: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/ResponseSchema.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/PromptBuilder.swift` (`Prompt` gains `jsonSchema`; `build` fills it)
- Test: `Packages/TimesheetCore/Tests/TimesheetCoreTests/ResponseSchemaTests.swift`, `PromptBuilderTests.swift`

**Interfaces:**
- Produces:
  - `public enum ResponseSchema { public static func json(keys: [String], activityTypes: [String], classifications: [String]) -> String }`
  - `Prompt.jsonSchema: String`. Add `jsonSchema: String = ""` as the last `Prompt.init` parameter so existing callers still compile.

**Schema shape (exact):**

```json
{"type":"object","additionalProperties":false,"required":["items"],
 "properties":{"items":{"type":"array","minItems":N,"maxItems":N,"items":false,
   "prefixItems":[ ITEM(e1), ITEM(e2), … ]}}}
```

`ITEM(k)` is the following object:

```json
{"type":"object","additionalProperties":false,
 "required":["key","minutes","fixedStart","fixedEnd","description","ticket","activityType","classification"],
 "properties":{
   "key":{"const":"k"},
   "minutes":{"type":"integer","minimum":1},
   "fixedStart":{"anyOf":[{"type":"string"},{"type":"null"}]},
   "fixedEnd":{"anyOf":[{"type":"string"},{"type":"null"}]},
   "description":{"type":"string"},
   "ticket":{"anyOf":[{"type":"string"},{"type":"null"}]},
   "activityType":{"enum":[…activityTypes]},
   "classification":{"enum":[…classifications]}}}
```

- Duplicate values are removed and first-seen order is kept. Values are otherwise unchanged (no trimming): the validator compares exact strings.
- An empty list becomes `{"type":"string"}`.
- Serialize with `JSONSerialization` and `.sortedKeys`, so output is deterministic. Order inside the `prefixItems` and `enum` arrays is preserved.
- No `pattern` on times. The validator already flags bad times.

- [ ] **Step 1: Write failing tests** in `ResponseSchemaTests.swift`. Decode the string with `JSONSerialization.jsonObject` and walk it.
  - `schemaHasOneItemPerKeyInOrder`: with keys `["e1","e2"]`, `prefixItems.count == 2`, `prefixItems[1].properties.key.const == "e2"`, `minItems == 2`, `maxItems == 2`, and `items` equals `false`.
  - `enumsComeFromSettingsLists`: `activityType.enum == ["Development","Meeting"]` and `classification.enum == ["Billable"]`.
  - `schemaEscapesAndDedupesValues`: activityTypes `["Dev \"QA\"", "C:\\path", "Réunion", "Dev \"QA\""]` decode back to the first three, in order.
  - `emptyListFallsBackToString`: with `activityTypes: []`, `activityType == ["type": "string"]`.
  - `nullableFieldsAllowNull`: the `ticket` anyOf contains `{"type":"null"}`, and `required` lists all 8 fields.
- [ ] **Step 2: Run them.** Run `swift test --package-path Packages/TimesheetCore --filter ResponseSchemaTests`. Expected: FAIL (`ResponseSchema` is undefined).
- [ ] **Step 3: Implement** `ResponseSchema.json`. Then, in `PromptBuilder.build`, set `jsonSchema` from the ordered keys (`e1…eN`) and `settings.activityTypes` / `settings.classifications`.
- [ ] **Step 4: Add a test to `PromptBuilderTests`.** `promptCarriesSchemaForItsKeys` checks that building with 3 entries gives a schema whose `prefixItems` keys are `e1,e2,e3`.
- [ ] **Step 5: Run the core suite.** Run `swift test --package-path Packages/TimesheetCore`. Expected: all pass.
- [ ] **Step 6: Commit** `feat(core): build a JSON Schema for the compile reply`.

### Task 2: Pass the schema through `LLMClient`; new incomplete-reply error

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/LLM/LLMClient.swift`
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/Compile/Compiler.swift:30`
- Test: `Packages/TimesheetCore/Tests/TimesheetCoreTests/CompilerTests.swift` (`FakeLLMClient` records the schema), plus whichever test file covers `LLMError.userMessage` (check `IssueMessagesTests.swift` / `CompileFailureTests.swift`; put the new test beside the existing message tests)

**Interfaces:**
- Consumes: `Prompt.jsonSchema` (Task 1).
- Produces:
  - The protocol requirement `func complete(system: String, user: String, jsonSchema: String?) async throws -> String`. Its default in `extension LLMClient` ignores the schema and calls `complete(system:user:)`. The doc comment says clients that can constrain decoding force the reply to match, and the others ignore the schema.
  - `LLMError.incompleteResponse` with `userMessage` = `"The model's answer was cut off before it finished. Try again."`

- [ ] **Step 1: Write failing tests.**
  - `compilerPassesSchemaToClient`: `FakeLLMClient` implements the 3-arg method and stores `lastSchema`. After a compile, `lastSchema == PromptBuilder.build(...).jsonSchema` and it is non-empty.
  - `incompleteResponseMessage`: asserts the exact message above.
  - `defaultOverloadIgnoresSchema`: a minimal client implementing only the 2-arg method returns its text when called with a schema.
- [ ] **Step 2: Run them.** Run `swift test --package-path Packages/TimesheetCore`. Expected: FAIL (compile errors).
- [ ] **Step 3: Implement** the protocol requirement plus its default. Add the error case and its message. In `Compiler`, call `client.complete(system:user:jsonSchema: prompt.jsonSchema)`. `OpenAICompatibleClient` is not touched.
- [ ] **Step 4: Run the core suite.** Expected: all pass, including the unchanged `OpenAICompatibleClientTests`.
- [ ] **Step 5: Commit** `feat(core): pass the reply schema to the LLM client`.

### Task 3: Constrained decoding in `MLXClient`

**Files:**
- Modify: `Packages/LocalModels/Package.swift`. Add `.product(name: "MLXGuidedGeneration", package: "mlx-swift-lm")` to the `LocalModels` target.
- Create: `Packages/LocalModels/Sources/LocalModels/GuidedJSON.swift`
- Modify: `Packages/LocalModels/Sources/LocalModels/MLXClient.swift`
- Test: `Packages/LocalModels/Tests/LocalModelsTests/GuidedJSONTests.swift`

**Interfaces:**
- Consumes:
  - `ResponseSchema.json`, `LLMError.incompleteResponse`, and the `LLMClient` 3-arg method (Tasks 1–2).
  - From mlx-swift-lm: `TokenizerVocabExtractor.extractForGrammar(from:)`, `GrammarTokenizer(vocab:vocabType:eosTokenId:)`, `GrammarConstraint(tokenizer:jsonSchema:fastForward:hostTokenizer:)`, `GuidedGenerationLoop.run(input:context:constraint:maxTokens:vocabSize:emit:)` and `GuidedGenerationError` (`.incompleteOutput`, `.prematureEOS`). Read `.build/checkouts/mlx-swift-lm/Libraries/MLXGuidedGeneration/README.md` ("Standalone on any MLX model") for the call sequence.
- Produces (internal to LocalModels):
  - `enum GuidedJSON`
    - `static func grammarTokenizer(for tokenizer: any MLXLMCommon.Tokenizer) throws -> GrammarTokenizer`
    - `static func mapError(_ error: Error) -> Error`. This maps `GuidedGenerationError` to `LLMError.incompleteResponse` and passes `CancellationError` and everything else through unchanged.
  - `MLXClient.complete(system:user:jsonSchema:)`. `complete(system:user:)` forwards to it with `nil`.

**Behaviour:**
- `jsonSchema` nil or empty: the existing unconstrained path, unchanged.
- Otherwise, inside `container.perform { context in … }`, prepare the same `UserInput` (with `enable_thinking: false`). Then build the `GrammarTokenizer`. Cache it on the actor and clear it whenever `loading` is reset; it's `@unchecked Sendable`, so return it out of `perform` to store it. Build `GrammarConstraint(fastForward: true, hostTokenizer: context.tokenizer)` and run `GuidedGenerationLoop.run` with `maxTokens: Self.maxTokens` and `vocabSize: grammarTokenizer.vocabSize`. Accumulate the deltas and return `!Task.isCancelled` from `emit`.
- If building the grammar tokenizer or the constraint throws (`GrammarError`), fall back to the unconstrained path for this call. Don't cache a failure. The parser and validator still guard the result.
- Errors from `run` go through `GuidedJSON.mapError`. Keep `try Task.checkCancellation()` after generation, then the existing trim and `emptyResponse` check.
- The guided loop samples greedily, so `temperature` doesn't apply there. Add a one-line comment saying so.

- [ ] **Step 1: Add the product dependency.** Run `cd Packages/LocalModels && xcodebuild build -scheme LocalModels -destination 'platform=macOS'`. Expected: BUILD SUCCEEDED (the xgrammar C++ compiles).
- [ ] **Step 2: Write failing tests in `GuidedJSONTests.swift`.** Use a toy `GrammarTokenizer`: vocab = each printable ASCII char `0x20…0x7E` as its own token, plus `"</s>"` as EOS, `vocabType: .raw`, with `fastForward: false`. Write a helper `accepts(_ json: String, schema: String) -> Bool` that commits one char-token at a time. It returns false when `commitToken` throws or when a char's bit is off in `computeMask()`. It returns true when the final mask allows EOS or `isTerminated`.
  - `compileSchemaIsAcceptedByXGrammar`: `GrammarConstraint(tokenizer:jsonSchema:)` with `ResponseSchema.json(keys: ["e1","e2"], activityTypes: ["Development","Meeting"], classifications: ["Billable"])` does not throw.
  - `validReplyIsAccepted`: a two-item reply with `null` fixed times and a ticket string returns true.
  - `unknownActivityTypeIsRejected`: `"activityType":"Coding"` returns false.
  - `wrongKeyOrderIsRejected`: items keyed `e2` then `e1` return false.
  - `missingItemIsRejected`: one item for two keys returns false.
  - `guidedErrorsMapToIncompleteResponse`: `mapError(GuidedGenerationError.incompleteOutput)` and `mapError(.prematureEOS)` are both `LLMError.incompleteResponse`, and `mapError(CancellationError())` is a `CancellationError`.
  - `setupFailureFallsBack`: `GrammarConstraint` with `jsonSchema: "not json"` throws a `GrammarError`. This proves the error the fallback catches is a `GrammarError`, so the fallback `catch` must target that type.
- [ ] **Step 3: Run them.** Run `cd Packages/LocalModels && xcodebuild test -scheme LocalModels -destination 'platform=macOS'`. Expected: FAIL (`GuidedJSON` is undefined).
- [ ] **Step 4: Implement** `GuidedJSON` and the `MLXClient` changes per the Behaviour list above.
- [ ] **Step 5: Run the LocalModels tests.** Expected: all pass, including the existing `MLXModelManagerTests`. The `modelNotReady` and `modelLoadFailed` paths are unchanged.
- [ ] **Step 6: Commit** `feat(local-models): constrain MLX output to the reply schema`.

### Task 4: App build and docs

**Files:**
- Modify: `CLAUDE.md`. In the Compile pipeline, step 2 now ends with: "With the on-device model, `MLXClient` constrains decoding to `ResponseSchema` (xgrammar via `MLXGuidedGeneration`), so the reply is always schema-valid JSON; the endpoint path is unconstrained." The LocalModels bullet gains "`GuidedJSON` builds the grammar constraint".
- Modify: `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md`. Add one sentence where the spec describes the model's JSON reply, matching the CLAUDE.md wording.

- [ ] **Step 1: Build the app.** Run `xcodegen generate && xcodebuild -project TimesheetAssistant.xcodeproj -scheme TimesheetAssistant -destination 'platform=macOS' build`. Expected: BUILD SUCCEEDED.
- [ ] **Step 2: Update the docs** as listed above.
- [ ] **Step 3: Commit** `docs: note constrained decoding for the on-device model`.
