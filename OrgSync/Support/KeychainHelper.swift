//
//  KeychainHelper.swift
//  OrgSync
//
//  Small wrapper around the Keychain Services API for storing secrets such as
//  the GitHub Personal Access Token. Kept intentionally tiny so it is easy to
//  reason about and, later, to move behind an App Group access group.
//

import Foundation
import Security

enum KeychainHelper {
    /// Service identifier used to namespace OrgSync's keychain items.
    static let service = "com.memohnsen.OrgSync"

    /// Stores (or updates) a string value for the given account key.
    /// Passing `nil` or an empty string removes the item.
    @discardableResult
    static func set(_ value: String?, account: String) -> Bool {
        guard let value, !value.isEmpty else {
            return delete(account: account)
        }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // AfterFirstUnlockThisDeviceOnly: the background push-on-close path
        // must still read the token after the device locks, and the secret
        // must never leave this device via backups. Included in updates too,
        // so items stored before this attribute existed migrate on write.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Reads the string value stored for the given account key, if any.
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Removes the stored value for the given account key.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
