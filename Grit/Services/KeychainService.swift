import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private init() {}

    enum Key: String, CaseIterable {
        case accessToken = "com.grit.gitlab.accessToken"
        case baseURL = "com.grit.gitlab.baseURL"
        case refreshToken = "com.grit.gitlab.refreshToken"
    }

    func save(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(for key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.retrieveFailed(status)
        }
        return string
    }

    func delete(for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    func clearAll() {
        Key.allCases.forEach { delete(for: $0) }
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case retrieveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let s): return "Keychain save failed: \(s)"
            case .retrieveFailed(let s): return "Keychain read failed: \(s)"
            }
        }
    }
}
