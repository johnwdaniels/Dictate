import Foundation

/// Short messages shown on the pill and in notifications. They never include an API key.
enum DictationFailure {
    static let missingKey = "Add an Inworld API key in Settings."
    static let rejectedKey = "The API key was rejected. Check it in Settings."
    static let connectionDropped = "The connection dropped. Try again."
    static let microphoneDenied = "Allow Microphone access for Dictate in System Settings."
    static let microphoneAllowed = "Microphone allowed. Press the shortcut again to dictate."
    static let accessibilityDenied = "Allow Accessibility for Dictate in System Settings. If Dictate is already on there, remove it with −, add it again, then quit and reopen Dictate."
    static let emptyTranscript = "No speech was transcribed."
    static let timedOut = "Transcription timed out. Try again."
    static let generic = "Something went wrong. Try again."
    static let keychain = "Couldn't read the saved API key. Save it again in Settings."

    static func message(for error: Error) -> String {
        if let error = error as? InworldSTTError {
            return error.localizedDescription
        }
        if let error = error as? PasteServiceError {
            return error.localizedDescription
        }
        if error is InworldAPIKeyStoreError {
            return keychain
        }
        if looksLikeRejectedKey(error) {
            return rejectedKey
        }
        if isNetwork(error) {
            return connectionDropped
        }
        return generic
    }

    static func serverMessage(_ raw: String) -> String {
        if looksLikeRejectedKey(raw) { return rejectedKey }
        var line = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        guard !line.isEmpty else { return generic }
        if let expression = try? NSRegularExpression(pattern: "(?i)basic\\s+\\S+") {
            let range = NSRange(line.startIndex..., in: line)
            line = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "Basic [key]")
        }
        guard line.count <= 90 else { return String(line.prefix(89)) + "…" }
        return line
    }

    /// A valid key can still be refused for one model. That is not a bad key, so the other model can be tried.
    static func looksLikeUnavailableModel(_ text: String) -> Bool {
        let value = text.lowercased()
        if value.contains("401") || value.contains("unauthor") || value.contains("unauthent") { return false }
        if value.contains("invalid api key") { return false }
        if value.contains("model") { return true }
        if value.contains("not found") || value.contains("not_found") { return true }
        if value.contains("unavailable") || value.contains("not available") || value.contains("not enabled") { return true }
        if value.contains("forbidden") || value.contains("403") { return true }
        if value.contains("permission denied") || value.contains("permission_denied") { return true }
        return false
    }

    static func looksLikeRejectedKey(_ text: String) -> Bool {
        if looksLikeUnavailableModel(text) { return false }
        let value = text.lowercased()
        if value.contains("401") { return true }
        if value.contains("unauthor") || value.contains("unauthent") { return true }
        if value.contains("invalid api key") || value.contains("api key") { return true }
        if value.contains("permission denied") { return true }
        return false
    }

    static func looksLikeRejectedKey(_ error: Error) -> Bool {
        let urlError = error as? URLError
        if urlError?.code == .userAuthenticationRequired || urlError?.code == .userCancelledAuthentication {
            return true
        }
        let nsError = error as NSError
        if let status = httpStatus(nsError), status == 401 { return true }
        return looksLikeRejectedKey(nsError.localizedDescription)
    }

    static func isNetwork(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func httpStatus(_ error: NSError) -> Int? {
        let keys = ["StatusCode", "statusCode", "NSHTTPStatusCode"]
        for key in keys {
            if let status = error.userInfo[key] as? Int { return status }
        }
        return nil
    }
}
