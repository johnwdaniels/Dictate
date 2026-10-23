import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global dictation shortcut. Settings can replace the initial Option-Space binding.
    static let startDictation = Self("startDictation", initial: .init(.space, modifiers: [.option]))

    /// Press once to keep recording. Press again to stop and paste.
    static let openRecording = Self("openRecording")
}
