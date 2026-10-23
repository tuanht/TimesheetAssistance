# Strict JSON for the Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the compile reply schema to the OpenAI-compatible endpoint as `response_format` so servers that support structured output (Ollama, llama.cpp, LM Studio, vLLM) constrain decoding, and fall back to an unconstrained request when the server rejects it.

**Architecture:** `OpenAICompatibleClient` implements the 3-argument `complete(system:user:jsonSchema:)`. With a schema it adds `response_format` to the chat request. If the server answers 400 or 422 to that request, it retries once without `response_format`. The 2-argument call (ticket summaries) is unchanged.

**Tech Stack:** Swift 6, Foundation `URLSession`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md` (Compile, step 3)

## Global Constraints

- The endpoint client refuses redirects; the retry goes through the same `send` path.
- User-facing error text never includes request bodies or raw model output.
- `ResponseParser` and `LineValidator` stay the guard for every reply, constrained or not.

## Decisions

- **Shape:** `"response_format": {"type": "json_schema", "json_schema": {"name": "timesheet_lines", "schema": <schema>}}`. No `"strict": true`: OpenAI's strict mode rejects `prefixItems`, `const` and `minItems`, which the schema needs.
- **Verbatim schema:** the schema string is embedded byte for byte, never re-parsed into a dictionary. Constrained decoders keep property order, and `key` must stay first. A schema string that is not valid JSON is ignored (plain request).
- **Fallback:** only HTTP 400 and 422 on the schema request trigger one plain retry. Every other error (401, 404, 503, timeout, redirect, cancellation) is thrown as before, with no retry.
- **Empty `jsonSchema`:** `nil` means a plain request, identical to the 2-argument call.

## Review Focus

- A server that ignores `response_format` and returns 200: the reply is used as is.
- Cancellation between the rejected request and the retry: no retry is sent.
- A 400 to the plain retry is reported as that 400, not swallowed.

---

### Task 1: Endpoint `response_format` with fallback

**Files:**
- Modify: `Packages/TimesheetCore/Sources/TimesheetCore/LLM/OpenAICompatibleClient.swift`
- Modify: `Packages/TimesheetCore/Tests/TimesheetCoreTests/OpenAICompatibleClientTests.swift` (`StubProtocol` gains a reply queue so a test can answer 400 then 200)
- Modify: `CLAUDE.md` (Compile pipeline step 2: drop "The endpoint path is unconstrained."; say the endpoint sends the schema as `response_format` and retries without it on 400/422)
- Modify: `docs/superpowers/specs/2026-10-22-timesheet-assistant-design.md:113` (replace "which is never constrained" accordingly)

**Interfaces:**
- Produces: `OpenAICompatibleClient.complete(system: String, user: String, jsonSchema: String?) async throws -> String`. The 2-argument `complete` calls it with `nil`.

- [ ] **Step 1: Write failing tests**
  - `sendsResponseFormatWithSchema`: schema `{"type":"object","properties":{"b":{},"a":{}}}`; body JSON has `response_format.type == "json_schema"`, `response_format.json_schema.name == "timesheet_lines"`, no `strict` key; the raw body string contains the schema text verbatim (order `b` before `a`).
  - `noResponseFormatWithoutSchema`: 2-arg call and 3-arg with `nil` send no `response_format`.
  - `invalidSchemaSendsPlainRequest`: `jsonSchema: "{not json"` sends no `response_format`, one request.
  - `retriesWithoutSchemaOn400` and `…On422`: replies 400 then 200 `"ok"`; result `"ok"`, two requests, the second has no `response_format`.
  - `noRetryOnOtherErrors`: 401 with schema throws `LLMError.http(401, _)` after one request; 503 throws `.modelNotReady` after one request.
  - `retryFailureIsReported`: 400 then 400; throws `LLMError.http(400, _)`, two requests.
- [ ] **Step 2: Run** `swift test --package-path Packages/TimesheetCore --filter OpenAICompatibleClientTests`. Expected: new tests fail.
- [ ] **Step 3: Implement.** Build the body by encoding `ChatRequest`, then splicing the `response_format` member before the closing brace when a valid schema is given. Check `Task.checkCancellation()` before the retry.
- [ ] **Step 4: Run** the full core suite `swift test --package-path Packages/TimesheetCore`. Expected: all pass.
- [ ] **Step 5: Update CLAUDE.md and the spec line, then commit** `feat(llm): send reply schema to the endpoint as response_format`.
