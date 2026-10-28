import SwiftUI

struct TranscriptionDebugView: View {
    @StateObject private var model = TranscriptionDebugModel()
    @AppStorage("inworldSTT.apiKey") private var apiKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("API key") {
                    SecureField("Basic credential", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Saved on this Mac for the debug view. It is not written into the project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Language") {
                    TextField("auto", text: $model.language)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Custom terms") {
                    TextField("Names or jargon, separated by commas", text: $model.promptsText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(model.isRecording)

            transcriptBox(title: "Committed", text: model.committed, dimmed: false)
            transcriptBox(title: "Interim", text: model.interim, dimmed: true)

            Text(model.status)
                .font(.callout)
                .foregroundStyle(model.failed ? Color.red : Color.secondary)
                .lineLimit(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            model.stop()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(model.isRecording ? "Stop" : "Record", systemImage: model.isRecording ? "stop.fill" : "record.circle") {
                    model.toggleRecording(apiKey: apiKey)
                }
                .labelStyle(.titleAndIcon)
                .prominentButton()
                .disabled(recordDisabled)
            }
        }
    }

    private var recordDisabled: Bool {
        !model.isRecording && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func transcriptBox(title: String, text: String, dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text.isEmpty ? " " : text)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .italic(dimmed && !text.isEmpty)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class TranscriptionDebugModel: ObservableObject {
    @Published var language = ""
    @Published var promptsText = ""
    @Published var committed = ""
    @Published var interim = ""
    @Published var status = "Ready"
    @Published var failed = false
    @Published var isRecording = false

    private let client = InworldSTTClient()
    private let capture = AudioRecorder()
    private var session: Task<Void, Never>?
    private var stopRequested = false

    func toggleRecording(apiKey: String) {
        if isRecording {
            stop()
        } else {
            begin(apiKey: apiKey)
        }
    }

    func stop() {
        stopRequested = true
        capture.stop()
    }

    private func begin(apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            failed = true
            status = InworldSTTError.missingAPIKey.localizedDescription
            return
        }

        stopRequested = false
        failed = false
        committed = ""
        interim = ""
        isRecording = true
        status = "Requesting microphone"
        let language = language
        let prompts = prompts(from: promptsText)

        session = Task {
            await bindClient()
            do {
                let stream = try await capture.start()
                if stopRequested {
                    capture.stop()
                    isRecording = false
                    status = "Ready"
                    return
                }
                status = "Connecting"
                try await client.start(apiKey: trimmedKey, language: language, prompts: prompts)
                if stopRequested {
                    capture.stop()
                    if await client.isStreaming {
                        await client.stop()
                    } else {
                        await client.cancel()
                        isRecording = false
                        status = "Ready"
                    }
                    return
                }
                status = "Listening"
                for await chunk in stream {
                    if stopRequested { break }
                    await client.sendAudio(chunk)
                }
                if await client.isStreaming {
                    status = "Finishing"
                    await client.stop()
                }
            } catch {
                capture.stop()
                await client.cancel()
                failed = true
                isRecording = false
                status = DictationFailure.message(for: error)
            }
            if !failed {
                isRecording = false
            }
        }
    }

    private func bindClient() async {
        await client.setHandlers(
            onInterim: { [weak self] text in
                Task { @MainActor in
                    self?.interim = text
                }
            },
            onFinal: { [weak self] segment in
                Task { @MainActor in
                    guard let self else { return }
                    self.committed = InworldSTTMessages.appending(self.committed, segment)
                    self.interim = ""
                }
            },
            onComplete: { [weak self] fullText in
                Task { @MainActor in
                    guard let self else { return }
                    let timedOut = await self.client.finishedByTimeout
                    self.committed = fullText
                    self.interim = ""
                    self.failed = false
                    self.isRecording = false
                    self.status = timedOut ? DictationFailure.timedOut : "Done"
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.capture.stop()
                    self.failed = true
                    self.isRecording = false
                    self.status = DictationFailure.message(for: error)
                }
            }
        )
    }

    private func prompts(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Text {
    func italic(_ enabled: Bool) -> Text {
        enabled ? self.italic() : self
    }
}
