import Foundation

/// Respuesta de `GET /status`: con ella sabe el emisor qué resolución admite la TV.
struct ReceiverStatus: Equatable {
    let name: String
    let maxW: Int
    let maxH: Int
    let busy: Bool

    static func parse(_ data: Data) throws -> ReceiverStatus {
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.maxW > 0,
            payload.maxH > 0
        else {
            throw SenderError.invalidStatus
        }
        return ReceiverStatus(
            name: payload.name ?? "TV",
            maxW: payload.maxW,
            maxH: payload.maxH,
            busy: payload.busy ?? false,
        )
    }

    // Todos los campos salvo maxW/maxH son opcionales en la spec: la app no debe
    // romperse si el receptor añade o quita claves.
    private struct Payload: Decodable {
        let name: String?
        let maxW: Int
        let maxH: Int
        let busy: Bool?
    }
}
