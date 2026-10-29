# Spoken text repair

Optional repair of a finished transcript, off unless the user turns it on. A second checkbox may also polish. Both use one Inworld chat completion on the API key Dictate already stores. A failure pastes the text Dictate already had.

## Settings

Two `UserDefaults` keys. A missing key is off, which is what `bool(forKey:)` returns.

| Key | Control | Effect |
| --- | --- | --- |
| `cleanup.repairSpokenText` | Toggle, **Repair spoken text** | Sends the transcript for repair. |
| `cleanup.polish` | Checkbox, **Polish** | Uses the polish prompt. Read as on only when repair is also on. |

Turning repair off leaves the polish value stored. Turning repair back on restores it. The checkbox is disabled while repair is off.

Both controls go in the existing Clean-up section of Settings, under the filler and number toggles. Help text:

- Repair: “Fixes self-corrections, grammar, and obvious transcription mistakes. The transcript is sent to Inworld, and paste waits for the result.”
- Polish: “Also tightens and rephrases, and keeps the meaning.”

Local clean-up is unchanged. Stray characters, filler words, and number formatting still run on this Mac under their own toggles, whether or not repair is on.

## Data flow

`DictationController.deliver` runs when the speech socket has closed. The pill is already in its processing state (spinner, no live words). Repair is awaited there, after dictionary replacements and before app style:

1. Trim the raw transcript. An empty result still reports the existing empty-transcript failure and does not call the model.
2. `TranscriptCleanup.clean`.
3. Dictionary replacements. An empty result still reports the empty-transcript failure and does not call the model.
4. `SpokenRepair.apply`. When repair is off, this returns the input and does not send a request.
5. `AppStyle.styled` for the frontmost app. A period the model added can still be dropped by a casual style, and a very-casual style can still lowercase sentence starts.
6. Paste, then save that styled text to history. History stores the same text it stores today: the styled transcript, before the paste layer adds a trailing space.

The shortcut already ignores presses while the phase is `.processing`. That phase stays `.processing` until `apply` returns. `deliver` is on the main actor and awaits a `nonisolated` function, so the wait suspends the actor instead of blocking it. `deliver` still checks `generation` before it starts, and checks it again after the await. If the generation changed, it returns without pasting and without setting the phase back to idle. It sets the phase to idle only after the await, once the generation still matches. Then it calls `dictationDidSucceed` and pastes, as it does today.

The Debug tab does not call `SpokenRepair`. It keeps showing the speech model’s transcript.

## Request

`SpokenRepair` lives in `Dictate/Input/SpokenRepair.swift`. The Dictate and test folders are synchronized Xcode groups, so the new files belong to their targets without a project edit.

`apply` loads the key with `InworldAPIKeyStore.load()`. A missing key, or a load error, returns the input and does not send a request. Repair off does the same. Polish off selects the repair prompt. Polish on, with repair on, selects the polish prompt.

```
POST https://api.inworld.ai/v1/chat/completions
Authorization: <InworldSTTMessages.authorizationValue>
Content-Type: application/json
```

The body is a JSON object with these fields. Tests decode the body. They do not depend on key order.

- `model`: `inworld/models/gemma-4-26b-a4b-it`
- `temperature`: `0`
- `stream`: `false`
- `max_tokens`: `min(4096, max(64, transcript.count / 3 + 64))`, using Swift’s `String.count` and integer division
- `messages`: a system message, then a user message whose content is the transcript alone

The request timeout is 1.5 seconds, on both the `URLRequest` and the session’s request and resource timeouts.

### Repair prompt

The system message is this text, and nothing else:

```
You edit a speech-to-text transcript. Return only the edited transcript.

Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

Fix grammar, agreement, and small words that were dropped. Fix words that are obvious mishearings from context.

Keep the language of the transcript. Keep names, numbers, and commitments. A question stays a question. Do not answer it. Do not add information. Do not tighten or rephrase beyond what the repair needs.

No preamble, label, or quotation marks around the result.
```

### Polish prompt

The system message is this text, and nothing else:

```
You edit a speech-to-text transcript. Return only the edited transcript.

Apply the speaker's later intention when they correct themselves. "Let's meet Tuesday, no, Wednesday" becomes "Let's meet Wednesday."

Fix grammar, agreement, small words that were dropped, and words that are obvious mishearings from context. You may tighten and rephrase.

Keep the meaning, the language, the names, the numbers, and the commitments. A question stays a question. Do not answer it. Do not add information.

No preamble, label, or quotation marks around the result.
```

## Accepting a reply

The reply is the OpenAI chat-completion shape: `choices[0].message.content` as a string, and `choices[0].finish_reason` as a string when present.

Accept the content only when all of these hold:

- The HTTP status is 200.
- `finish_reason` is absent or any value other than `length`.
- After trimming whitespace and newlines, the content is non-empty.
- If the trimmed string is wrapped in one pair, strip that pair and trim again. The pairs are straight double quotes (`"` … `"`), curly double quotes (`“` … `”`), and straight single quotes (`'` … `'`). A transcript that is itself one quoted sentence can lose those outer quotes. Strip once.
- The result is non-empty, and its `count` is at most `max(input.count * 2, input.count + 80)`.

Any other outcome returns the input text. That includes a timeout, a cancelled request, a non-200 status, malformed JSON, a null or non-string `content`, `finish_reason` of `length`, an empty result, and a result over the length cap. A long transcript whose `max_tokens` cap of 4096 cuts the reply off is one of these cases: the user gets the unrepaired text.

Dictate does not show an error and does not post a notice. It prints one line, `[SpokenRepair] <reason>`, with no transcript and no API key. Paste and history then proceed with the input text, still passed through app style.

## Tests

`DictateTests/SpokenRepairTests.swift` uses a `UserDefaults` suite and a transport closure `(URLRequest) async throws -> (Data, URLResponse)`. No test calls Inworld.

- Repair and polish read as off when the keys are missing.
- Polish reads as off when its key is on and repair is off. `apply` does not call the transport.
- Repair on and polish off builds a body with the repair system prompt, the transcript as the user message, model `inworld/models/gemma-4-26b-a4b-it`, temperature 0, and `stream` false. `max_tokens` follows the formula above.
- Repair on and polish on builds the polish system prompt instead.
- A missing key does not call the transport, and `apply` returns the input.
- A 200 response with a normal string is returned, with one wrapping quote pair removed.
- An empty body, a non-200 status, `finish_reason` of `length`, a thrown timeout, and a string longer than the cap all return the input.
- The transport is not called when repair is off.

## Out of scope

Streaming tokens into the pill, a per-app repair switch, translating, changing the local filler or number toggles, and running repair on the Debug tab.
