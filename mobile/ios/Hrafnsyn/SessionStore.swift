import Foundation
import Security

/// Credentials are scoped to the canonical origin. Passwords are never stored.
struct SessionStore {
    private let service = "io.hrafnsyn.mobile.sessions"

    func read(server: String) throws -> SavedSession? {
        var query = key(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw StorageError(status: status) }
        return try JSONDecoder().decode(StoredSession.self, from: data).value
    }

    func write(_ session: SavedSession?, server: String) throws {
        guard let session else {
            let status = SecItemDelete(key(server) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError(status: status) }
            return
        }
        let data = try JSONEncoder().encode(StoredSession(session))
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(key(server) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(key(server).merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw StorageError(status: status) }
        } else if status != errSecSuccess { throw StorageError(status: status) }
    }

    private func key(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: server]
    }

    struct StorageError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Unable to save your session securely. Unlock this device and try again. (\(status))" }
    }

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let accessExpiresAt: Int64
        let refreshExpiresAt: Int64
        let sessionId: String
        let username: String
        init(_ value: SavedSession) {
            accessToken = value.accessToken; refreshToken = value.refreshToken
            accessExpiresAt = value.accessExpiresAt; refreshExpiresAt = value.refreshExpiresAt
            sessionId = value.sessionId; username = value.username
        }
        var value: SavedSession {
            SavedSession(accessToken: accessToken, refreshToken: refreshToken, accessExpiresAt: accessExpiresAt,
                         refreshExpiresAt: refreshExpiresAt, sessionId: sessionId, username: username)
        }
    }
}
