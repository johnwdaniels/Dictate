import AppKit
import AVFoundation
import SwiftUI

enum Onboarding {
    static let completeKey = "onboarding.complete"
}

/// First-launch sheet for the API key, microphone, and Accessibility.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var keyMessage: String?
    @State private var microphone = PermissionState.unknown
    @State private var accessibility = false

    private var ready: Bool {
        keySaved && microphone == .allowed && accessibility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Dictate")
                .font(.title2)
            Text("Three things are needed before the first dictation.")
                .foregroundStyle(.secondary)

            step(done: keySaved, title: "Inworld API key") {
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save key", action: saveKey)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let keyMessage {
                        Text(keyMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }

            step(done: microphone == .allowed, title: "Microphone") {
                switch microphone {
                case .allowed:
                    Text("Microphone access is on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .denied:
                    Text("Microphone access is off.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(SystemSettingsLink.microphone)
                    }
                case .unknown:
                    Button("Allow Microphone", action: requestMicrophone)
                }
            }

            step(done: accessibility, title: "Accessibility") {
                Text(accessibility ? "Accessibility access is on." : AccessibilityPermission.needsRestartNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !accessibility {
                    Button("Open System Settings") {
                        AccessibilityPermission.prompt()
                        NSWorkspace.shared.open(SystemSettingsLink.accessibility)
                    }
                    Button("Quit and reopen", action: AccessibilityPermission.quitAndReopen)
                }
            }

            HStack {
                Spacer()
                Button("Later") { dismiss() }
                Button("Continue") {
                    UserDefaults.standard.set(true, forKey: Onboarding.completeKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .task(id: accessibility) {
            guard !accessibility else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refresh()
            }
        }
    }

    private func step<Content: View>(done: Bool, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.primary : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refresh() {
        do {
            if try InworldAPIKeyStore.load() != nil {
                keySaved = true
                keyMessage = nil
            }
        } catch {
            keyMessage = DictationFailure.keychain
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphone = .allowed
        case .denied, .restricted:
            microphone = .denied
        case .notDetermined:
            microphone = .unknown
        @unknown default:
            microphone = .unknown
        }
        accessibility = AccessibilityPermission.isTrusted
    }

    private func saveKey() {
        do {
            try InworldAPIKeyStore.save(apiKey)
            apiKey = ""
            keySaved = true
            keyMessage = nil
        } catch {
            keySaved = false
            keyMessage = error.localizedDescription
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                refresh()
            }
        }
    }

}

private enum PermissionState {
    case unknown
    case allowed
    case denied
}
