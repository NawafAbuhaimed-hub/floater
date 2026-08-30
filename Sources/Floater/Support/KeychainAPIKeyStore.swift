import FloaterCore
import Foundation
import Security

/// Stores the Anthropic API key as a Keychain generic password. It never
/// touches UserDefaults or any file, so it is not readable from the app's
/// preferences plist.
final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "com.nawaf.floater"
    private let account = "anthropic-api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func write(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
