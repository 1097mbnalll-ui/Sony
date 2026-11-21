// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Security

/// Minimal Keychain wrapper (generic passwords, this device only).
enum Keychain {
    private static let service = "tarjuman"

    static func set(_ data: Data?, for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            LogStore.shared.error("Keychain write failed (\(status)) for \(key)")
        }
    }

    static func get(_ key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func setString(_ value: String?, for key: String) {
        set(value.flatMap { $0.data(using: .utf8) }, for: key)
    }

    static func getString(_ key: String) -> String? {
        get(key).flatMap { String(data: $0, encoding: .utf8) }
    }
}
