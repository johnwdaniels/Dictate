# Spoken Text Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an off-by-default repair pass that sends a finished transcript to Inworld's hosted Gemma, with a polish checkbox, and paste the unrepaired text when that call fails.

**Architecture:** `SpokenRepair` owns the preference reads, the chat-completion request, and the reply check. `DictationController.deliver` awaits it after dictionary replacements and before app style, while the pill stays on its processing spinner. Settings adds the two controls to the existing Clean-up section.

**Tech Stack:** Swift 5, SwiftUI, XCTest, `URLSession`, the existing Inworld API key and `Authorization` helper.

## Global Constraints

- Repair key `cleanup.repairSpokenText` and polish key `cleanup.polish`. A missing key is off.
- Polish is on only when both keys are on. Turning repair off keeps the stored polish value.
- One request: `POST https://api.inworld.ai/v1/chat/completions`, model `inworld/models/gemma-4-26b-a4b-it`, temperature 0, `stream` false.
- `max_tokens` is `min(4096, max(64, transcript.count / 3 + 64))`.
- Timeout is 1.5 seconds on the `URLRequest` and on the session's request and resource timeouts.
- Authorization is `InworldSTTMessages.authorizationValue(apiKey:)`.
- A non-200, timeout, empty reply, `finish_reason` of `length`, or a reply longer than `max(input.count * 2, input.count + 80)` pastes the input. No error UI. Log `[SpokenRepair] <reason>` with no transcript and no key.
- The Debug tab is unchanged. Local filler and number clean-up is unchanged.
- New files under `Dictate/` and `DictateTests/` are picked up by the synchronized Xcode groups.

---

### Task 1: Request body and reply check

**Files:**
- Create: `Dictate/Input/SpokenRepair.swift`
- Test: `DictateTests/SpokenRepairTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `SpokenRepair.repairKey`, `SpokenRepair.polishKey`, `SpokenRepair.repairIsOn(in:)`, `SpokenRepair.polishIsOn(in:)`, `SpokenRepair.maxTokens(for:)`, `SpokenRepair.repairPrompt`, `SpokenRepair.polishPrompt`, `SpokenRepair.requestBody(transcript:polish:) throws -> Data`, `SpokenRepair.acceptedText(from:status:input:) -> String?`

- [x] **Step 1: Write the failing test**

Create `DictateTests/SpokenRepairTests.swift` with the tests in that file in the implementation (preferences, both prompts, `max_tokens`, quote stripping, and every reject path).

- [x] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES test -only-testing:DictateTests/SpokenRepairTests`

Expected: FAIL to compile because `SpokenRepair` does not exist.

- [x] **Step 3: Write the minimal implementation**

Add `Dictate/Input/SpokenRepair.swift` with the prompts, the JSON body, and `acceptedText`. `apply` can wait for Task 2.

- [x] **Step 4: Run the test to verify it passes**

Same `xcodebuild` command. Expected: the Task 1 tests PASS. Task 2 tests still fail until `apply` exists, so land Task 1 and Task 2 before requiring the whole class to pass.

- [x] **Step 5: Commit**

```bash
git add Dictate/Input/SpokenRepair.swift DictateTests/SpokenRepairTests.swift
git commit -m "Add the spoken-repair request and reply check."
```

### Task 2: Send the request and fall back

**Files:**
- Modify: `Dictate/Input/SpokenRepair.swift`
- Test: `DictateTests/SpokenRepairTests.swift`

**Interfaces:**
- Consumes: Task 1
- Produces: `SpokenRepair.endpoint`, `SpokenRepair.Transport`, `SpokenRepair.apply(_:defaults:loadKey:transport:) async -> String`

- [x] **Step 1: Write the failing tests**

Cover repair off (polish stored, transport not called), a missing or throwing key, a successful send (URL, timeout 1.5, Basic authorization, repaired text), and fallback on an empty body, non-200, `length`, an over-long reply, and a thrown timeout.

- [x] **Step 2: Run to verify failure**

Expected: FAIL because `apply` does not exist.

- [x] **Step 3: Implement `apply`**

When repair is off, return the input and do not load the key or call the transport. Otherwise load the key. Nil or a thrown error prints `[SpokenRepair] missing key` and returns the input. Build the request with `requestBody`. A thrown encode prints `[SpokenRepair] request`. The default transport uses an ephemeral `URLSession` with both timeouts at 1.5. A thrown send prints `[SpokenRepair] transport`. A nil `acceptedText` prints `[SpokenRepair] reply`. A non-HTTP response counts as status 0.

- [x] **Step 4: Run the tests**

Expected: `SpokenRepairTests` PASS.

- [x] **Step 5: Commit**

```bash
git add Dictate/Input/SpokenRepair.swift DictateTests/SpokenRepairTests.swift
git commit -m "Fall back to the original transcript when repair fails."
```

### Task 3: Settings and the paste path

**Files:**
- Modify: `Dictate/Views/SettingsView.swift` (the `@AppStorage` list near the top, and `cleanupSection`)
- Modify: `Dictate/App/DictationController.swift` (`runSession` call around line 388, and `deliver` around line 430)

**Interfaces:**
- Consumes: `SpokenRepair.apply(_:)`
- Produces: the Settings controls and the await inside `deliver`

- [x] **Step 1: Add the controls**

```swift
@AppStorage(SpokenRepair.repairKey) private var repairSpokenText = false
@AppStorage(SpokenRepair.polishKey) private var polishSpokenText = false
```

Under the number-format help in `cleanupSection`:

```swift
Toggle("Repair spoken text", isOn: $repairSpokenText)
Text("Fixes self-corrections, grammar, and obvious transcription mistakes. The transcript is sent to Inworld, and paste waits for the result.")
    .font(.callout)
    .foregroundStyle(.secondary)
Toggle("Polish", isOn: $polishSpokenText)
    .disabled(!repairSpokenText)
Text("Also tightens and rephrases, and keeps the meaning.")
    .font(.callout)
    .foregroundStyle(.secondary)
```

A `Toggle` in this macOS form is the checkbox. Polish stays disabled while repair is off, and its stored value is left alone.

- [x] **Step 2: Await repair inside `deliver`**

Change the call in `runSession` to `await self.deliver(outcome.snapshot(), generation: generation)`.

Make `deliver` `async`. Do not use `defer` to set `.idle`, because that would run after the await and could clear a newer session. Set `phase = .idle` on the error and empty-transcript returns. After dictionary replacements:

```swift
let repaired = await SpokenRepair.apply(replaced)
guard self.generation == generation else { return }
phase = .idle
```

Style `repaired`, then succeed, paste, and save history as today. The Debug tab is not modified.

- [x] **Step 3: Run the full test suite**

Run: `xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES test`

Expected: TEST SUCCEEDED.

- [x] **Step 4: Commit**

```bash
git add Dictate/Views/SettingsView.swift Dictate/App/DictationController.swift
git commit -m "Repair a transcript after dictation when the setting is on."
```
