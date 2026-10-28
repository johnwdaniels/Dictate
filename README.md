# Dictate

Native macOS menu bar dictation app written in Swift and SwiftUI. It requires macOS 14 or later.

## Install

1. Download the latest `Dictate-v….zip` from [Releases](https://github.com/johnwdaniels/Dictate/releases). It runs on Apple silicon and Intel.
2. Unzip it and move **Dictate.app** to Applications.
3. Open Dictate. The first time, macOS says it can't verify the developer, because releases are signed ad-hoc instead of with a paid Apple Developer ID. Open **System Settings → Privacy & Security**, scroll to the message about Dictate, click **Open Anyway**, and confirm.

Each release is a new ad-hoc signature, so macOS treats an update as a different app. After updating, turn Dictate off and on again under **Privacy & Security → Accessibility**, then use **Quit and reopen** in Settings. Microphone access may be asked for again.

To publish a release, push a version tag. GitHub Actions runs the tests, builds the app, and attaches the zip to a release named after the tag.

```sh
git tag v1.1.0
git push origin v1.1.0
```

## Build from source

1. Open `Dictate.xcodeproj` in Xcode.
2. Run the Dictate scheme, or build it from the command line:

```sh
xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES build
open "build/Build/Products/Debug/Dictate.app"
```

3. The app starts in the menu bar. Choose **Open Dictate** to show the window. The first launch opens that window and a short setup sheet.

Unit tests:

```sh
xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES test
```

While Dictate is only in the menu bar there is no Dock icon. Opening the window makes it a normal app so it can take keyboard focus. Closing the window hides the Dock icon again. The menu bar item contains **Open Dictate** and **Quit**.

The global shortcut starts dictation. Hold to talk and Toggle are in Settings. The shortcut starts as Option-Space and can be changed there. A shortcut must include a modifier. The Debug tab can still record a clip on its own and keeps its key separate from the one used by the shortcut.

## Inworld API key

The key is stored in the Keychain (`com.johndaniels.Dictate`), not in UserDefaults or a plist.

- On first launch, the setup sheet has a field for it. Save the key there.
- Later, open **Settings**, paste the key into the Inworld API key field, and leave the field so it is saved. **Test connection** opens a short WebSocket session and reports whether the key was accepted. **Remove key** deletes it from the Keychain.

Dictate sends the key as the `Authorization` value. If it already starts with `basic `, it is sent as-is. It is not printed in logs.

## Permissions

Dictate needs two permissions:

- **Microphone**, so it can record speech.
- **Accessibility**, so the global shortcut can be heard while another app is focused and so the finished transcript can be pasted into that app.

The setup sheet asks for both and shows a checkmark as each one is granted. Settings has the same status rows. **Open System Settings** jumps to Privacy & Security → Microphone or Accessibility. If macOS has already denied Microphone access, the system prompt will not appear again; turn Dictate on in that pane.

Dictate is signed with a local certificate named Dictate Local, so the Accessibility switch keeps working after a rebuild. macOS still applies that switch only to a Dictate that starts after you turn it on. Use **Quit and reopen** on the setup sheet. That quits this copy and opens it again. It does not leave a second Dictate running.

**Launch at login** uses `SMAppService`. A debug build that is not in `/Applications` may need approval under System Settings → General → Login Items. The error is shown next to the toggle.

## Known limits

- The custom dictionary holds at most **100 terms**. That is Inworld’s cap for the `prompts` array sent with each session. The terms are a soft bias toward names and jargon, not a guaranteed match. If there are no terms, the field is omitted.
- A term may contain letters in any script, decimal digits, spaces, and these characters: `. , ' ( ) : ! ? ; -`. Anything else is rejected, and the message names the character. A straight double quote is not allowed. The clean-up button turns curly quotes (`“ ” ‘ ’`) into a straight apostrophe and turns `_` into a space. Import does not clean lines; it skips them.
- Replacements (find → replace) are applied on this Mac after transcription. They are not sent to Inworld. Matching is case-insensitive, prefers the longer phrase, and does not change a match that sits inside a longer word.
- **The app is not sandboxed.** `ENABLE_APP_SANDBOX` is `NO` on the Dictate target, and `Dictate/Dictate.entitlements` sets `com.apple.security.app-sandbox` to false. A global hotkey and Accessibility paste cannot work inside the App Sandbox. Leave the sandbox off.
