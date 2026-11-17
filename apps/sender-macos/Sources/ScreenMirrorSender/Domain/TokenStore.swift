import Foundation

/// Almacén de tokens de emparejamiento, uno por TV (`host`).
///
/// Es un protocolo para que `domain` no conozca el Keychain y la UI se pueda testear.
protocol TokenStore {
    func token(forHost host: String) -> String?
    func save(token: String, forHost host: String) throws
    func removeToken(forHost host: String) throws
}
