import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(DictationListenMode.storageKey) private var listenMode = DictationListenMode.holdOrTap.rawValue
    @AppStorage(DictationLanguage.storageKey) private var languageCode = DictationLanguage.defaultCode
    @AppStorage(FloatingIndicator.visibilityKey) private var hideIndicator = false
    @AppStorage(FloatingIndicator.liveTextKey) private var showLiveText = true
    @AppStorage(StartSound.storageKey) private var startSound = StartSound.ding.rawValue
    @AppStorage(PastePreferences.clickAtMouseKey) private var clickAtMouse = false
    @AppStorage(PastePreferences.trailingSpaceKey) private var trailingSpace = true
    @AppStorage(InputDevices.storageKey) private var inputDeviceUID = ""
    @AppStorage(TranscriptCleanup.removeFillersKey) private var removeFillers = true
    @AppStorage(TranscriptCleanup.formatNumbersKey) private var formatNumbers = true
    @AppStorage(ScreenContext.enabledKey) private var useScreenNames = true
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
    @State private var testMessage: String?
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
            whileDictatingSection
            languageSection
            StyleSection()
            cleanupSection
            aiEditingSection
            pasteSection
            permissionsSection
            generalSection
        }
        .glassForm()
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
        Section("Shortcut") {
            LabeledContent {
                ShortcutRecorderField()
                    .fixedSize()
            } label: {
                SettingLabel(title: "Dictation", systemImage: "keyboard", color: .blue)
            }
            Picker(selection: $listenMode) {
                ForEach(DictationListenMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                SettingLabel(
                    title: "Mode",
                    subtitle: (DictationListenMode(rawValue: listenMode) ?? .holdOrTap).summary,
                    systemImage: "hand.tap.fill",
                    color: .indigo
                )
            }
            if accessibilityStatus != "Allowed", let modifier = ModifierKey.stored(for: .startDictation) {
                Text("\(modifier.title) on its own needs Accessibility, which is off. Fix it under Permissions below.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            LabeledContent {
                ShortcutRecorderField(name: .openRecording)
                    .fixedSize()
            } label: {
                SettingLabel(
                    title: "Open recording",
                    subtitle: "Press once to start, and again to stop and paste.",
                    systemImage: "record.circle",
                    color: .red
                )
            }
            LabeledContent {
                ShortcutRecorderField(name: .pasteLastDictation)
                    .fixedSize()
            } label: {
                SettingLabel(title: "Paste last dictation", systemImage: "doc.on.clipboard.fill", color: .teal)
            }
        }
    }

    private var microphoneSection: some View {
        Section("Microphone") {
            Picker(selection: $inputDeviceUID) {
                Text(inputDevices.defaultName.isEmpty ? "System default" : "System default (\(inputDevices.defaultName))")
                    .tag("")
                if !inputDeviceUID.isEmpty, !inputDevices.devices.contains(where: { $0.uid == inputDeviceUID }) {
                    Text("Saved microphone (not connected)").tag(inputDeviceUID)
                }
                ForEach(inputDevices.devices) { device in
                    Text(device.name).tag(device.uid)
                }
            } label: {
                SettingLabel(title: "Input device", systemImage: "mic.fill", color: .orange)
            }
        }
        .onAppear(perform: inputDevices.startListening)
        .onDisappear(perform: inputDevices.stopListening)
    }

    private var cleanupSection: some View {
        Section("Clean-up") {
            Toggle(isOn: $removeFillers) {
                SettingLabel(
                    title: "Remove filler words",
                    subtitle: "Removes “um”, “uh” and “you know” when it is set off by commas.",
                    systemImage: "scissors",
                    color: .pink
                )
            }
            Toggle(isOn: $formatNumbers) {
                SettingLabel(
                    title: "Format numbers",
                    subtitle: "Writes “ninety days” as “90 days” and “fifty percent” as “50%”. One to nine stay as words.",
                    systemImage: "number",
                    color: .purple
                )
            }
            Toggle(isOn: $useScreenNames) {
                SettingLabel(
                    title: "Spell names the way the screen shows them",
                    subtitle: "Reads the windows on your screens and sends Inworld only the unusual names on them.",
                    systemImage: "text.viewfinder",
                    color: .blue
                )
            }
        }
    }

    /// The only settings that send the transcript off the Mac, so they sit apart from the local clean-up.
    private var aiEditingSection: some View {
        Section {
            Toggle(isOn: $repairSpokenText) {
                SettingLabel(
                    title: "Fix self-corrections and grammar",
                    subtitle: "“Tuesday, no, Wednesday” becomes “Wednesday.” Also fixes grammar and misheard words, and otherwise keeps your wording.",
                    systemImage: "wand.and.stars",
                    color: .purple
                )
            }
            Toggle(isOn: $polishSpokenText) {
                SettingLabel(
                    title: "Also tighten wording",
                    subtitle: "May shorten and reword sentences while keeping the meaning. Better for messages than for exact wording.",
                    systemImage: "text.badge.minus",
                    color: .indigo
                )
            }
                .disabled(!repairSpokenText)
        } header: {
            Text("AI editing")
        } footer: {
            Text("Sends the transcript to an AI model through Inworld. Pasting can wait up to 1.5 seconds.")
        }
    }

    private var whileDictatingSection: some View {
        Section("While dictating") {
            // Choosing a sound plays it.
            Picker(selection: $startSound) {
                ForEach(StartSound.allCases) { sound in
                    Text(sound.title).tag(sound.rawValue)
                }
            } label: {
                SettingLabel(title: "Start sound", systemImage: "speaker.wave.2.fill", color: .pink)
            }
            .onChange(of: startSound) { _, _ in
                StartChime.play()
            }
            Toggle(isOn: Binding(
                get: { !hideIndicator },
                set: { hideIndicator = !$0 }
            )) {
                SettingLabel(title: "Show the recording pill", systemImage: "waveform", color: .green)
            }
            Toggle(isOn: $showLiveText) {
                SettingLabel(title: "Show live text in the pill", systemImage: "text.bubble.fill", color: .cyan)
            }
                .disabled(hideIndicator)
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker(selection: languageSelection) {
                Text("Auto-detect").tag("")
                ForEach(DictationLanguage.options, id: \.code) { option in
                    Text(option.name).tag(option.code)
                }
            } label: {
                SettingLabel(title: "Language", systemImage: "globe", color: .blue)
            }
        }
    }

    private var pasteSection: some View {
        Section("Paste") {
            Toggle(isOn: $clickAtMouse) {
                SettingLabel(title: "Click at mouse position before pasting", systemImage: "cursorarrow.click.2", color: .orange)
            }
            Toggle(isOn: $trailingSpace) {
                SettingLabel(title: "Add a trailing space after each dictation", systemImage: "space", color: .gray)
            }
            Button(testRunning ? "Pasting…" : "Test paste") {
                runPasteTest()
            }
            .disabled(testRunning)
            if let testMessage {
                Text(testMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            LabeledContent {
                HStack {
                    Text(microphoneStatus)
                        .foregroundStyle(.secondary)
                    if microphoneStatus != "Allowed" {
                        Button("Open Settings") {
                            open(SystemSettingsLink.microphone)
                        }
                        .accessibilityLabel("Open Microphone settings")
                    }
                }
            } label: {
                SettingLabel(title: "Microphone", systemImage: "mic.fill", color: .orange)
            }
            LabeledContent {
                HStack {
                    Text(accessibilityStatus)
                        .foregroundStyle(.secondary)
                    if accessibilityStatus != "Allowed" {
                        Button("Open Settings") {
                            AccessibilityPermission.prompt()
                            open(SystemSettingsLink.accessibility)
                        }
                        .accessibilityLabel("Open Accessibility settings")
                    }
                }
            } label: {
                SettingLabel(title: "Accessibility", systemImage: "accessibility", color: .blue)
            }
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

    private var generalSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { updateLaunchAtLogin($0) }
            )) {
                SettingLabel(title: "Launch at login", systemImage: "power", color: .green)
            }
            if let loginStatus {
                Text(loginStatus)
                    .font(.callout)
                    .foregroundStyle(loginFailed ? Color.red : Color.secondary)
            }
            UpdateRows()
        } header: {
            Text("General")
        } footer: {
            MadeWithLove()
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
                testMessage = "Click the text field to paste into. Pasting “Dictate test” in \(remaining)…"
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

/// The sign-off at the very bottom of Settings.
private struct MadeWithLove: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            HStack(spacing: 5) {
                Text("A Labor of Love from John & Pedro")
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .symbolEffect(.pulse)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Sparkle's automatic updates, in the General section.
private struct UpdateRows: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )) {
            SettingLabel(title: "Check for updates automatically", systemImage: "arrow.triangle.2.circlepath", color: .blue)
        }
        Toggle(isOn: Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
        )) {
            SettingLabel(title: "Download and install updates automatically", systemImage: "arrow.down.circle.fill", color: .indigo)
        }
        .disabled(!updater.automaticallyChecksForUpdates)
        LabeledContent {
            HStack {
                Text(AppUpdater.currentVersion)
                    .foregroundStyle(.secondary)
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        } label: {
            SettingLabel(title: "Version", systemImage: "info", color: .gray)
        }
    }
}

enum SystemSettingsLink {
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
}
