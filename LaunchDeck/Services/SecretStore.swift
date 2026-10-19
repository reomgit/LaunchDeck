// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import LocalAuthentication

protocol SecretProviding: Sendable {
    func secret(reference: String) throws -> String
}
/// Keychain values never become part of extension manifests or profile packages.
struct SecretStore: SecretProviding {
    let service: String
    init(service: String = "org.launchdeck.http-secrets") { self.service = service }
    func secret(reference: String) throws -> String {
        var query = base(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw EcosystemError("Configure local secret \(reference) in Extensions before running this action.") }
        return value
    }
    func save(_ value: String, reference: String) throws {
        guard !reference.isEmpty, reference.count <= 200, value.utf8.count <= 32_768 else { throw EcosystemError("Invalid secret reference or value.") }
        let query = base(reference)
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = Data(value.utf8)
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(create as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw EcosystemError("Could not save local secret to Keychain (\(status)).") }
    }
    func remove(reference: String) throws {
        let status = SecItemDelete(base(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw EcosystemError("Could not remove local secret (\(status)).") }
    }
    private func base(_ reference: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: reference]
    }
}
