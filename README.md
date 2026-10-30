# Dictator

Native macOS menu bar dictation app written in Swift and SwiftUI. It requires macOS 14 or later.

It used to be called Dictate. The bundle ID, the "Dictate Release" certificate, the API key folder and the log subsystem keep the old name, so updates, Accessibility and saved settings carry over. A copy installed before the rename keeps its `Dictate.app` file name, because Sparkle installs an update where the old copy is.

The app icon is a Liquid Glass Icon Composer document, `Dictate/AppIcon.icon`. **Settings → App icon** offers five more, which change the icon the running app shows in the Dock, the app switcher and Settings; Finder keeps the built-in one. Their sources are in `design/app-icons`.

## Install

1. Download the latest `Dictator-v….zip` from [Releases](https://github.com/johnwdaniels/Dictate/releases). It runs on Apple silicon and Intel.
2. Unzip it and move **Dictator.app** to Applications.
3. Open Dictator. The first time, macOS says it can't verify the developer, because releases are signed with a self-signed certificate instead of a paid Apple Developer ID. Open **System Settings → Privacy & Security**, scroll to the message about Dictator, click **Open Anyway**, and confirm.
4. Allow Accessibility when asked, then use **Quit and reopen** in Settings.

Dictator checks for updates once a day with [Sparkle](https://sparkle-project.org). When a new release is out, it downloads it in the background and installs it once the Mac has had no keyboard or mouse input for three minutes and no dictation is running, then relaunches. If that never happens, it installs when Dictator quits. **Check for Updates…** in the menu bar checks right away, and **Settings → Updates** can turn the daily check off, or turn off automatic install so Dictator asks first. Every release is signed with the same "Dictate Release" certificate, so macOS treats the update as the same app and Accessibility stays on.

The feed is `appcast.xml` on the latest release. GitHub only serves release files to signed-out visitors when the repository is public, so automatic updates start working once it is. If the repository moves, change the `DICTATE_APPCAST_URL` build setting.

If Settings says Accessibility is off while System Settings shows Dictator on, the switch belongs to an earlier copy, such as one built in Xcode. Click **Reset Accessibility** in Settings, turn Dictator on again, then **Quit and reopen**.

### Publishing a release

Write the notes first, in `release-notes/<tag>.md` (for example `release-notes/v1.2.0.md`), following the voice in [release-notes/README.md](release-notes/README.md). Then push a version tag. GitHub Actions runs the tests, builds the app, signs it with the release certificate, and attaches the zip and the update feed to a release named after the tag. The notes file goes on top, with GitHub's list of merged pull requests under it. Without a notes file the run shows a warning.

```sh
git tag v1.2.0
git push origin v1.2.0
```

Releases need three repository secrets, set once by the repository owner under **Settings → Secrets and variables → Actions**:

- `DICTATE_SIGNING_P12`: the base64 text of the "Dictate Release" certificate and key (`.p12`).
- `DICTATE_SIGNING_PASSWORD`: that file's password.
- `SPARKLE_ED_PRIVATE_KEY`: the private EdDSA key that signs each update. Its public half is `SUPublicEDKey` in `Dictate/Info.plist`.

Keep using the same certificate and the same Sparkle key. A new certificate makes every Mac treat the next update as a different app, and a new Sparkle key makes installed copies reject updates. Without the signing secrets, the release is signed ad-hoc and Accessibility won't carry over. Without the Sparkle key, the release has no update feed. Either way, the run shows a warning.

## Build from source

1. Open `Dictate.xcodeproj` in Xcode.
2. Run the Dictate scheme, or build it from the command line:

```sh
xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES build
open "build/Build/Products/Debug/Dictator.app"
```

3. The app starts in the menu bar. Choose **Open Dictator** to show the window. The first launch opens that window and a short setup sheet.

Unit tests:

```sh
xcodebuild -project Dictate.xcodeproj -scheme Dictate -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=YES test
```

While Dictator is only in the menu bar there is no Dock icon. Opening the window makes it a normal app so it can take keyboard focus. Closing the window hides the Dock icon again. The menu bar item contains **Open Dictator** and **Quit**.

The global shortcut starts dictation. It starts as Hold or tap: hold the shortcut to talk, or tap it to start and tap again to stop. Hold to talk and Toggle are in Settings. The shortcut starts as Option-Space and can be changed there. A shortcut must include a modifier.

## Inworld API key

The key is stored in `~/Library/Application Support/Dictate/inworld-api-key`, readable only by your user account, not in UserDefaults or a plist. It used to be in the Keychain, but without an Apple team ID macOS asked for the login password after every update. A key saved there by an older version moves to the file the first time Dictator reads it.

- On first launch, the setup sheet has a field for it. Save the key there.
- Later, open **Settings**, paste the key into the Inworld API key field, and leave the field so it is saved. **Test connection** opens a short WebSocket session and reports whether Inworld answered and accepted the key. **Remove key** deletes it.

Dictator sends the key as the `Authorization` value. If it already starts with `basic `, it is sent as-is. It is not printed in logs.

## Troubleshooting

When a dictation comes back empty, the message says why:

- **Couldn't reach Inworld.** Inworld never answered. A VPN, proxy or firewall is usually holding the connection open without letting replies through. Exclude `api.inworld.ai` from the VPN or from HTTPS inspection, or try another network.
- **The microphone sent only silence.** The audio that went out never rose above about -60 dBFS. Check the input chosen in Settings and the input level in System Settings → Sound.
- **No speech was transcribed.** Inworld got live audio and found no words.

**Test connection** sends a tenth of a second of silence and waits up to five seconds for Inworld to answer.

Dictator logs each session's microphone format, how much audio it sent and how loud it was, and what Inworld answered. Entries never include the key or the transcript. To read the last ten minutes:

```sh
/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.johndaniels.Dictate"'
```

## Permissions

Dictator needs two permissions:

- **Microphone**, so it can record speech.
- **Accessibility**, so the global shortcut can be heard while another app is focused and so the finished transcript can be pasted into that app.

The setup sheet asks for both and shows a checkmark as each one is granted. Settings has the same status rows. **Open System Settings** jumps to Privacy & Security → Microphone or Accessibility. If macOS has already denied Microphone access, the system prompt will not appear again; turn Dictator on in that pane.

Dictator is signed with a local certificate named Dictate Local, so the Accessibility switch keeps working after a rebuild. macOS still applies that switch only to a Dictator that starts after you turn it on. Use **Quit and reopen** on the setup sheet. That quits this copy and opens it again. It does not leave a second Dictator running.

**Launch at login** uses `SMAppService`. A debug build that is not in `/Applications` may need approval under System Settings → General → Login Items. The error is shown next to the toggle.

## Known limits

- The custom dictionary holds at most **100 terms**. That is Inworld’s cap for the `prompts` array sent with each session. The terms are a soft bias toward names and jargon, not a guaranteed match. If there are no terms, the field is omitted.
- A term may contain letters in any script, decimal digits, spaces, and these characters: `. , ' ( ) : ! ? ; -`. Anything else is rejected, and the message names the character. A straight double quote is not allowed. The clean-up button turns curly quotes (`“ ” ‘ ’`) into a straight apostrophe and turns `_` into a space. Import does not clean lines; it skips them.
- Replacements (find → replace) are applied on this Mac after transcription. They are not sent to Inworld. Matching is case-insensitive, prefers the longer phrase, and does not change a match that sits inside a longer word.
- **The app is not sandboxed.** `ENABLE_APP_SANDBOX` is `NO` on the Dictate target, and `Dictate/Dictate.entitlements` sets `com.apple.security.app-sandbox` to false. A global hotkey and Accessibility paste cannot work inside the App Sandbox. Leave the sandbox off.
