import Foundation
import Security

/// Keychain item Settings uses for the Inworld API key.
enum InworldAPIKeyStore {
    static let service = "com.johndaniels.Dictate"
    static let account = "inworldAPIKey"

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw InworldAPIKeyStoreError(status: status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw InworldAPIKeyStoreError(status: errSecDecode)
        }
        return key
    }

    static func save(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw InworldSTTError.missingAPIKey
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleted = SecItemDelete(query as CFDictionary)
        if deleted != errSecSuccess && deleted != errSecItemNotFound {
            throw InworldAPIKeyStoreError(status: deleted)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw InworldAPIKeyStoreError(status: status)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw InworldAPIKeyStoreError(status: status)
    }
}

struct InworldAPIKeyStoreError: Error, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String?, !message.isEmpty {
            return "Keychain error: \(message)"
        }
        return "Keychain error (\(status))."
    }
}
