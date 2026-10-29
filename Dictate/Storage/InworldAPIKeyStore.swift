import Foundation
import Security

/// The Inworld API key, in a file only the signed-in user can read
/// (`~/Library/Application Support/Dictate/inworld-api-key`, mode 0600).
///
/// It used to live in the Keychain. Releases are signed with a self-signed certificate that has no Apple team ID, so
/// macOS ties a Keychain item to the exact build that saved it and asked for the login password after every update.
/// A key still in the Keychain moves to the file the first time it is read, and the Keychain item is removed.
enum InworldAPIKeyStore {
    static let service = "com.johndaniels.Dictate"
    static let account = "inworldAPIKey"

    /// Tests point this at a temporary folder.
    nonisolated(unsafe) static var directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dictate", isDirectory: true)
    /// Tests turn this off so they never touch the real Keychain.
    nonisolated(unsafe) static var migratesFromKeychain = true

    static var fileURL: URL {
        directory.appendingPathComponent("inworld-api-key")
    }

    static func load() throws -> String? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw InworldAPIKeyStoreError(status: errSecIO)
            }
            guard let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !key.isEmpty else {
                throw InworldAPIKeyStoreError(status: errSecDecode)
            }
            return key
        }
        guard migratesFromKeychain, let key = try LegacyKeychain.load() else { return nil }
        try save(key)
        return key
    }

    static func save(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw InworldSTTError.missingAPIKey
        }
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Created with 0600 before the key is written, so it is never readable by others, even briefly.
            let staging = directory.appendingPathComponent(".inworld-api-key-\(UUID().uuidString)")
            guard manager.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw InworldAPIKeyStoreError(status: errSecIO)
            }
            let handle = try FileHandle(forWritingTo: staging)
            try handle.write(contentsOf: data)
            try handle.close()
            _ = try manager.replaceItemAt(fileURL, withItemAt: staging)
        } catch let error as InworldAPIKeyStoreError {
            throw error
        } catch {
            throw InworldAPIKeyStoreError(status: errSecIO)
        }
        if migratesFromKeychain {
            LegacyKeychain.delete()
        }
    }

    static func delete() throws {
        if migratesFromKeychain {
            LegacyKeychain.delete()
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw InworldAPIKeyStoreError(status: errSecIO)
        }
    }
}

/// Where the key was kept before it moved to a file. Only read once, to move it.
private enum LegacyKeychain {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: InworldAPIKeyStore.service,
            kSecAttrAccount as String: InworldAPIKeyStore.account,
        ]
    }

    static func load() throws -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &item)
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

    static func delete() {
        _ = SecItemDelete(query as CFDictionary)
    }
}

struct InworldAPIKeyStoreError: Error, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String?, !message.isEmpty {
            return "Couldn't read the saved API key: \(message)"
        }
        return "Couldn't read the saved API key (\(status))."
    }
}
