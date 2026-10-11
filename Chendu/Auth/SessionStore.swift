import Foundation
import Security

protocol SecretStore {
    func read(account: String) -> Data?
    func write(account: String, data: Data) throws
    func delete(account: String)
}

final class MemorySecrets: SecretStore {
    var values: [String: Data] = [:]
    func read(account: String) -> Data? { values[account] }
    func write(account: String, data: Data) throws { values[account] = data }
    func delete(account: String) { values[account] = nil }
}

struct KeychainStore: SecretStore {
    var service: String = "com.scoheart.chendu.session"

    func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(account: String, data: Data) throws {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw AuthError.http(Int(status)) }
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@Observable
final class SessionStore {
    static let live = SessionStore(secrets: KeychainStore())

    private let secrets: SecretStore
    private let account = "session"
    private(set) var session: AuthSession?

    init(secrets: SecretStore) {
        self.secrets = secrets
        session = Self.decode(secrets.read(account: "session"))
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try secrets.write(account: account, data: data)
        self.session = session
    }

    func clear() {
        secrets.delete(account: account)
        session = nil
    }

    private static func decode(_ data: Data?) -> AuthSession? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}
