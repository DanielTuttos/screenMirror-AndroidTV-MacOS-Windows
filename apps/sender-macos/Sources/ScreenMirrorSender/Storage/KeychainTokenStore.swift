import Foundation
import Security

/// `TokenStore` sobre el Keychain (contraseña genérica, una entrada por TV).
///
/// El token da acceso a emitir a esa TV durante 24 h: no debe quedar en disco en claro.
struct KeychainTokenStore: TokenStore {
    /// Configurable para que los tests no toquen las entradas reales de la app.
    let service: String

    init(service: String = "tv.screenmirror.sender.token") {
        self.service = service
    }

    func token(forHost host: String) -> String? {
        var query = baseQuery(forHost: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(token: String, forHost host: String) throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(forHost: host) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(forHost: host)
            attributes[kSecValueData as String] = data
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func removeToken(forHost host: String) throws {
        let status = SecItemDelete(baseQuery(forHost: host) as CFDictionary)
        // Borrar algo que no existe no es un error: el estado deseado ya se cumple.
        if status != errSecItemNotFound { try check(status) }
    }

    private func baseQuery(forHost host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }
}

enum KeychainError: Error, LocalizedError {
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "Error del Keychain: \(message)"
        }
    }
}
