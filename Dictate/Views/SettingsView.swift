import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(DictationListenMode.storageKey) private var listenMode = DictationListenMode.holdToTalk.rawValue
    @AppStorage(DictationLanguage.storageKey) private var languageCode = ""
    @AppStorage(FloatingIndicator.visibilityKey) private var hideIndicator = false
    @AppStorage(FloatingIndicator.liveTextKey) private var showLiveText = true
    @AppStorage(StartSound.storageKey) private var startSound = StartSound.ding.rawValue
    @AppStorage(PastePreferences.clickAtMouseKey) private var clickAtMouse = false
    @AppStorage(PastePreferences.trailingSpaceKey) private var trailingSpace = true
    @AppStorage(InputDevices.storageKey) private var inputDeviceUID = ""
    @AppStorage(TranscriptCleanup.removeFillersKey) private var removeFillers = true
    @AppStorage(TranscriptCleanup.formatNumbersKey) private var formatNumbers = true
    @AppStorage(SpokenRepair.repairKey) private var repairSpokenText = false
    @AppStorage(SpokenRepair.polishKey) private var polishSpokenText = false
    @StateObject private var inputDevices = InputDeviceList()

    @State private var apiKey = ""
    @State private var keyStatus: String?
    @State private var keyFailed = false
    @State private var testingConnection = false
    @State private var microphoneStatus = "Not requested"
    @State private var accessibilityStatus = "Off"
    @State private var launchAtLogin = false
    @State private var loginStatus: String?
    @State private var loginFailed = false
    @State private var testMessage = "You have 3 seconds to click the text field that should receive the text."
    @State private var testRunning = false

    private var languageSelection: Binding<String> {
        Binding {
            DictationLanguage.options.contains { $0.code == languageCode } ? languageCode : ""
        } set: { languageCode = $0 }
    }

    var body: some View {
        Form {
            apiKeySection
            shortcutSection
            microphoneSection
            indicatorSection
            startSoundSection
            languageSection
            StyleSection()
            cleanupSection
            pasteSection
            permissionsSection
            loginSection
            UpdatesSection()
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadKey()
            refreshPermissions()
            refreshLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            refreshLogin()
        }
    }

    private var apiKeySection: some View {
        Section("Inworld API key") {
            SecureField("API key", text: $apiKey)
                .onSubmit(saveKey)
            if let keyStatus {
                Text(keyStatus)
                    .font(.callout)
                    .foregroundStyle(keyFailed ? Color.red : Color.secondary)
            }
            HStack {
                Button(testingConnection ? "Testing…" : "Test connection") {
                    testConnection()
                }
                .disabled(testingConnection)
                Button("Remove key") {
                    removeKey()
                }
                .disabled(testingConnection)
            }
        }
    }

    private var shortcutSection: some View {
        Section("Dictation shortcut") {
            LabeledContent("Dictation shortcut") {
                ShortcutRecorderField()
                    .fixedSize()
            }
            Picker("Mode", selection: $listenMode) {
                ForEach(DictationListenMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            Text("Shortcuts must include Command, Option, or Control, or be a right-side modifier on its own, such as Right Option. Hold to talk records while the shortcut is held. Toggle starts and stops on each press. Hold or tap does both: hold to record until you let go, or tap once to start and again to stop.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if accessibilityStatus != "Allowed", let modifier = ModifierKey.stored(for: .startDictation) {
                Text("\(modifier.title) on its own needs Accessibility, which is off. Fix it under Permissions below.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            LabeledContent("Open recording") {
                ShortcutRecorderField(name: .openRecording)
                    .fixedSize()
            }
            Text("Press once to start. Press the same shortcut again to stop and paste. You do not have to hold it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var microphoneSection: some View {
        Section("Microphone") {
            Picker("Input device", selection: $inputDeviceUID) {
                Text(inputDevices.defaultName.isEmpty ? "System default" : "System default (\(inputDevices.defaultName))")
                    .tag("")
                if !inputDeviceUID.isEmpty, !inputDevices.devices.contains(where: { $0.uid == inputDeviceUID }) {
                    Text("Saved microphone (not connected)").tag(inputDeviceUID)
                }
                ForEach(inputDevices.devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            Text("When the chosen microphone is not connected, Dictate records from the system default.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: inputDevices.startListening)
        .onDisappear(perform: inputDevices.stopListening)
    }

    private var cleanupSection: some View {
        Section("Clean-up") {
            Toggle("Remove filler words", isOn: $removeFillers)
            Text("Removes “um”, “uh” and “you know” when it is set off by commas.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Format numbers", isOn: $formatNumbers)
            Text("Writes “ninety days” as “90 days” and “fifty percent” as “50%”. One to nine stay as words.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Repair spoken text", isOn: $repairSpokenText)
            Text("Fixes self-corrections, grammar, and obvious transcription mistakes. The transcript is sent to Inworld, and paste waits for the result.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Polish", isOn: $polishSpokenText)
                .disabled(!repairSpokenText)
            Text("Also tightens and rephrases, and keeps the meaning.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var indicatorSection: some View {
        Section("Indicator") {
            Toggle("Hide the recording indicator", isOn: $hideIndicator)
            Toggle("Show live text", isOn: $showLiveText)
                .disabled(hideIndicator)
            Text("A small pill above the Dock while you dictate. It does not take focus. Turn off live text to see only the waveform; errors still show.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var startSoundSection: some View {
        Section("Start sound") {
            Picker("Start sound", selection: $startSound) {
                ForEach(StartSound.allCases) { sound in
                    Text(sound.title).tag(sound.rawValue)
                }
            }
            .onChange(of: startSound) { _, _ in
                StartChime.play()
            }
            Button("Play sound") {
                StartChime.play()
            }
            .disabled(startSound == StartSound.off.rawValue)
            Text("Plays when transcription starts. Off starts recording in silence.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: languageSelection) {
                Text("Auto-detect").tag("")
                ForEach(DictationLanguage.options, id: \.code) { option in
                    Text("\(option.name) (\(option.code))").tag(option.code)
                }
            }
            Text("A language is a hint. Auto-detect leaves the choice to the model.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Link("Language Support", destination: DictationLanguage.documentationURL)
                .font(.callout)
        }
    }

    private var pasteSection: some View {
        Section("Paste behavior") {
            Toggle("Click at mouse position before pasting", isOn: $clickAtMouse)
            Toggle("Add a trailing space after each dictation", isOn: $trailingSpace)
            Button(testRunning ? "Pasting…" : "Paste “Dictate test”") {
                runPasteTest()
            }
            .disabled(testRunning)
            Text(testMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            LabeledContent("Microphone") {
                Text(microphoneStatus)
                    .foregroundStyle(.secondary)
            }
            Button("Open System Settings") {
                open(SystemSettingsLink.microphone)
            }
            .accessibilityLabel("Open Microphone settings")
            LabeledContent("Accessibility") {
                Text(accessibilityStatus)
                    .foregroundStyle(.secondary)
            }
            Button("Open System Settings") {
                AccessibilityPermission.prompt()
                open(SystemSettingsLink.accessibility)
            }
            .accessibilityLabel("Open Accessibility settings")
            if accessibilityStatus != "Allowed" {
                Text(AccessibilityPermission.needsRestartNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reset Accessibility", action: AccessibilityPermission.resetAndAsk)
                    Button("Quit and reopen", action: AccessibilityPermission.quitAndReopen)
                }
            }
        }
    }

    private var loginSection: some View {
        Section("Launch at login") {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { updateLaunchAtLogin($0) }
            ))
            if let loginStatus {
                Text(loginStatus)
                    .font(.callout)
                    .foregroundStyle(loginFailed ? Color.red : Color.secondary)
            }
        }
    }

    private func loadKey() {
        do {
            apiKey = try InworldAPIKeyStore.load() ?? ""
        } catch {
            reportKey(error)
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try InworldAPIKeyStore.save(trimmed)
            keyStatus = "Key saved."
            keyFailed = false
        } catch {
            reportKey(error)
        }
    }

    private func removeKey() {
        do {
            try InworldAPIKeyStore.delete()
            apiKey = ""
            keyStatus = "Key removed."
            keyFailed = false
        } catch {
            reportKey(error)
        }
    }

    private func testConnection() {
        let key = apiKey
        testingConnection = true
        keyStatus = nil
        Task {
            do {
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try InworldAPIKeyStore.save(trimmed)
                }
                try await InworldConnectionTest.check(apiKey: key, language: DictationLanguage.storedCode)
                keyStatus = "Connected."
                keyFailed = false
            } catch {
                reportKey(error)
            }
            testingConnection = false
        }
    }

    private func reportKey(_ error: Error) {
        keyStatus = error.localizedDescription
        keyFailed = true
    }

    private func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = "Allowed"
        case .denied:
            microphoneStatus = "Off"
        case .restricted:
            microphoneStatus = "Restricted"
        case .notDetermined:
            microphoneStatus = "Not requested"
        @unknown default:
            microphoneStatus = "Unknown"
        }
        accessibilityStatus = AccessibilityPermission.isTrusted ? "Allowed" : "Off"
    }

    private func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            if loginStatus == nil || !loginFailed {
                loginStatus = nil
            }
        case .requiresApproval:
            launchAtLogin = true
            loginStatus = "Approve Dictate in System Settings > General > Login Items."
            loginFailed = false
        case .notRegistered, .notFound:
            launchAtLogin = false
        @unknown default:
            launchAtLogin = false
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginFailed = false
            loginStatus = nil
            refreshLogin()
        } catch {
            loginStatus = error.localizedDescription
            loginFailed = true
            refreshLogin()
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func runPasteTest() {
        testRunning = true
        Task {
            for remaining in [3, 2, 1] {
                testMessage = "Pasting “Dictate test” in \(remaining)…"
                try? await Task.sleep(for: .seconds(1))
            }
            do {
                try await PasteService.paste("Dictate test")
                testMessage = "Pasted “Dictate test”."
            } catch {
                testMessage = error.localizedDescription
            }
            testRunning = false
        }
    }
}

/// Settings for Sparkle's automatic updates.
private struct UpdatesSection: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            Toggle("Download and install updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.automaticallyDownloadsUpdates = $0 }
            ))
            .disabled(!updater.automaticallyChecksForUpdates)
            LabeledContent("Version", value: AppUpdater.currentVersion)
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

enum SystemSettingsLink {
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
}
