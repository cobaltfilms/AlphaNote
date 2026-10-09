import Foundation
import Security

enum KeychainServiceError: LocalizedError {
    case unexpectedData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned unexpected data."
        case let .osStatus(status):
            return "Keychain error (\(status))."
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.cobaltfilms.alphanote.nextcloud"

    private init() {}

    func savePassword(_ password: String, serverURL: String, username: String) throws {
        let account = accountKey(serverURL: serverURL, username: username)
        let encoded = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encoded
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainServiceError.osStatus(updateStatus)
        }

        var createQuery = query
        createQuery[kSecValueData as String] = encoded

        let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
        guard createStatus == errSecSuccess else {
            throw KeychainServiceError.osStatus(createStatus)
        }
    }

    func readPassword(serverURL: String, username: String) throws -> String? {
        let account = accountKey(serverURL: serverURL, username: username)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.unexpectedData
        }

        return password
    }

    func deletePassword(serverURL: String, username: String) throws {
        let account = accountKey(serverURL: serverURL, username: username)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw KeychainServiceError.osStatus(status)
    }

    private func accountKey(serverURL: String, username: String) -> String {
        "\(username.lowercased())|\(serverURL.lowercased())"
    }

    func saveGenericSecret(_ secret: String, service: String, account: String) throws {
        let encoded = Data(secret.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encoded
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainServiceError.osStatus(updateStatus)
        }

        var createQuery = query
        createQuery[kSecValueData as String] = encoded

        let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
        guard createStatus == errSecSuccess else {
            throw KeychainServiceError.osStatus(createStatus)
        }
    }

    func readGenericSecret(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }

        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.unexpectedData
        }

        return secret
    }

    func deleteGenericSecret(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw KeychainServiceError.osStatus(status)
    }
}
