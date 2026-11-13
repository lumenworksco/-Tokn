import Foundation
import Security

enum KeychainError: LocalizedError {
    case notFound
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound:              return "Session key not found in Keychain"
        case .saveFailed(let s):     return "Keychain save failed: \(s)"
        case .deleteFailed(let s):   return "Keychain delete failed: \(s)"
        case .encodingFailed:        return "Failed to encode session key"
        }
    }
}

final class KeychainRepository: Sendable {
    /// Slot used before multi-account support; only read during migration.
    static let legacyAccount = "session-key"

    private let service = "com.tokn.app"
    private let account: String

    init(account: String) {
        self.account = account
    }

    func save(_ value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let existing = SecItemCopyMatching(lookup as CFDictionary, nil)

        if existing == errSecSuccess {
            // Item exists — update in place (avoids auth failure from delete+add cycle)
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        } else {
            // No existing item — add with explicit accessibility
            var add = lookup
            add[kSecValueData as String]   = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        }
    }

    func retrieve() throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.notFound }
            throw KeychainError.saveFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }

        return value
    }

    func exists() -> Bool {
        (try? retrieve()) != nil
    }

    @discardableResult
    func delete() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.deleteFailed(status) }
        return true
    }
}
