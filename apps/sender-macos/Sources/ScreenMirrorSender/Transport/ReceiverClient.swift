import Foundation

/// Cliente de los endpoints de control (`GET /status` y `POST /pair`).
/// El stream largo no va por aquí: para eso está `StreamClient` (NWConnection + chunked).
struct ReceiverClient {
    var session: URLSession = .shared
    var timeout: TimeInterval = 5

    func fetchStatus(host: String) async throws -> ReceiverStatus {
        let url = try endpoint(host: host, path: Protocol.pathStatus)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SenderError.connectionFailed("respuesta no HTTP")
        }
        switch http.statusCode {
        case 200: return try ReceiverStatus.parse(data)
        case 401: throw SenderError.unauthorized
        default: throw SenderError.unexpectedStatus(http.statusCode)
        }
    }

    /// PIN → token de sesión (256 bits). El token caduca a las 24 h o cuando la TV se reinicia.
    func pair(host: String, pin: String) async throws -> String {
        guard pin.count == Protocol.pinLength, pin.allSatisfy(\.isNumber) else {
            throw SenderError.pairingRejected("el PIN debe tener \(Protocol.pinLength) dígitos")
        }
        let url = try endpoint(host: host, path: Protocol.pathPair)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PinPayload(pin: pin))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SenderError.connectionFailed("respuesta no HTTP")
        }
        switch http.statusCode {
        case 200:
            guard let token = try? JSONDecoder().decode(TokenPayload.self, from: data).token,
                  !token.isEmpty
            else { throw SenderError.malformedResponse }
            return token
        case 401: throw SenderError.pairingRejected("PIN incorrecto")
        case 429: throw SenderError.pairingRejected("demasiados intentos: espera un minuto")
        default: throw SenderError.unexpectedStatus(http.statusCode)
        }
    }

    private func endpoint(host: String, path: String) throws -> URL {
        // IPv6 (p. ej. fe80::…%en0 que resuelve mDNS): URLComponents rechaza la zona,
        // así que se construye a mano con los corchetes y %25 escapado (RFC 6874).
        if host.contains(":") {
            let escaped = host.replacingOccurrences(of: "%", with: "%25")
            guard let url = URL(string: "http://[\(escaped)]:\(Protocol.port)\(path)") else {
                throw SenderError.connectionFailed("dirección inválida: \(host)")
            }
            return url
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(Protocol.port)
        components.path = path
        guard let url = components.url else {
            throw SenderError.connectionFailed("dirección inválida: \(host)")
        }
        return url
    }

    private struct PinPayload: Encodable { let pin: String }
    private struct TokenPayload: Decodable { let token: String }
}
