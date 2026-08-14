import Foundation
import Security

// Note: no kSecAttrAccessGroup in these queries. Both targets list the same
// shared group first in their keychain-access-groups entitlement, so iOS
// defaults every keychain call to that group — specifying it manually would
// require hardcoding the team ID prefix (e.g. "AB12CD34EF.com...shared").
enum KeychainHelper {
    /// Returns whether the token actually landed in the Keychain. The caller has
    /// to check: the app's "connected" state is otherwise inferred from an
    /// in-memory copy of the token, so a rejected write (a provisioning or
    /// entitlement mismatch, which is exactly the sort of thing that differs
    /// between a local build and a fresh TestFlight install) left the app
    /// showing "Connected ✓" while the widget had nothing to read. That
    /// presents as "the widget is broken" with no trace of the real cause.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess { lastSaveStatus = status }
        return status == errSecSuccess
    }

    /// Kept so a rejected write can be named in a diagnostic rather than
    /// vanishing into a generic failure message.
    nonisolated(unsafe) static var lastSaveStatus: OSStatus?

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
