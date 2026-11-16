import Foundation
import Network

/// Transporte del stream: `POST /stream` con cuerpo **chunked** sobre NWConnection.
///
/// URLSession no sirve aquí: necesitamos ir soltando cada access unit en cuanto sale
/// del codificador, sin bufferizar el vídeo entero ni esperar a `uploadTask`.
/// El receptor ya soporta chunked (lo usa ffmpeg), así que hablamos su idioma.
final class StreamClient {
    private struct Constants {
        static let headerEnd = Data("\r\n\r\n".utf8)
        static let crlf = Data("\r\n".utf8)
    }

    private let connection: NWConnection
    private let host: String
    private let path: String
    private let contentType: String
    private let queue = DispatchQueue(label: "tv.screenmirror.sender.stream")
    private var continuation: CheckedContinuation<Int, Error>?
    private var headerBuffer = Data()
    private var didResolveResponse = false
    private var isFinished = false

    /// Avisos de desconexión (la TV cierra el stream o se cae la red).
    var onDisconnect: ((Error) -> Void)?

    init(
        host: String,
        port: UInt16 = Protocol.port,
        path: String = Protocol.pathStream,
        contentType: String = Protocol.contentTypeAnnexB,
    ) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SenderError.connectionFailed("puerto inválido: \(port)")
        }
        self.host = host
        self.path = path
        self.contentType = contentType
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp,
        )
    }

    /// Abre la conexión, envía la cabecera HTTP y devuelve el código de respuesta.
    /// Cualquier código distinto de 200 lanza: 409 (ocupada), 413 (resolución), 401 (token).
    func open(query: String) async throws -> Int {
        // Últimos dos elementos vacíos = el \r\n final que separa cabeceras de cuerpo.
        let head = [
            "POST \(path)?\(query) HTTP/1.1",
            "Host: \(host):\(Protocol.port)",
            "Content-Type: \(contentType)",
            "Transfer-Encoding: chunked",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connection.send(content: Data(head.utf8), completion: .contentProcessed { error in
                    if let error { self.fail(error) }
                })
                self.receiveHeaders()
            case .failed(let error):
                self.fail(error)
            default:
                break
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            connection.start(queue: queue)
        }
    }

    /// Envía un chunk del cuerpo (access unit H.264 o bloque PCM) como chunk HTTP.
    func send(_ bytes: Data) {
        guard !isFinished else { return }
        var chunk = Data("\(String(bytes.count, radix: 16))\r\n".utf8)
        chunk.append(bytes)
        chunk.append(Constants.crlf)
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error) }
        })
    }

    /// Cierra el cuerpo chunked y la conexión. Cierre de conexión = fin de sesión en el receptor.
    /// Espera a que salga el terminador ("0\r\n\r\n"): si cancelamos antes, la TV ve un RST.
    func close() async {
        guard !isFinished else { return }
        isFinished = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { _ in
                self.connection.cancel()
                continuation.resume()
            })
        }
    }

    // MARK: - Privado

    private func receiveHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.fail(error); return }
            if let data { self.headerBuffer.append(data) }

            if let range = self.headerBuffer.range(of: Constants.headerEnd) {
                let head = self.headerBuffer.subdata(in: self.headerBuffer.startIndex..<range.lowerBound)
                self.resolveResponse(head)
                return
            }
            if isComplete {
                self.fail(SenderError.connectionFailed("la TV cerró antes de responder"))
                return
            }
            self.receiveHeaders()
        }
    }

    private func resolveResponse(_ head: Data) {
        guard !didResolveResponse else { return }
        didResolveResponse = true

        guard
            let line = String(data: head, encoding: .isoLatin1)?.split(separator: "\r\n").first,
            let code = line.split(separator: " ").dropFirst().first.flatMap({ Int($0) })
        else {
            fail(SenderError.malformedResponse)
            return
        }

        if code == 200 {
            continuation?.resume(returning: code)
        } else {
            continuation?.resume(throwing: Self.error(forStatusCode: code))
        }
        continuation = nil
    }

    private func fail(_ error: Error) {
        let resolved = !didResolveResponse
        didResolveResponse = true
        if resolved, let continuation {
            self.continuation = nil
            continuation.resume(throwing: error)
        } else if !isFinished {
            onDisconnect?(error)
        }
    }

    private static func error(forStatusCode code: Int) -> SenderError {
        switch code {
        case 401: return .unauthorized
        case 409: return .receiverBusy
        case 413: return .resolutionNotSupported(w: 0, h: 0)
        default: return .unexpectedStatus(code)
        }
    }
}
