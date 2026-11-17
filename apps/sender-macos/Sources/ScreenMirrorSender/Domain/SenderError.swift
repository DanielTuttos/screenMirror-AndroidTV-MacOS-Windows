import Foundation

/// Errores tipados del emisor. Nada de `catch {}` vacío: cada fallo se puede mostrar y reintentar.
enum SenderError: Error, Equatable {
    case screenRecordingDenied
    case displayNotFound
    case pairingRejected(String)
    case receiverBusy
    case unauthorized
    case resolutionNotSupported(w: Int, h: Int)
    case connectionFailed(String)
    case unexpectedStatus(Int)
    case encoderFailed(String)
    case audioUnavailable(String)
    case invalidStatus
    case malformedResponse
}

extension SenderError: LocalizedError {
    // Mensajes para la persona que usa la app: en español.
    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "Activa el permiso de Grabación de pantalla en Ajustes › Privacidad."
        case .displayNotFound:
            return "La pantalla seleccionada ya no existe."
        case .pairingRejected(let reason):
            return "Emparejamiento rechazado: \(reason)"
        case .receiverBusy:
            return "La TV ya está emitiendo con otro dispositivo."
        case .unauthorized:
            return "Token inválido o caducado: vuelve a emparejar con el PIN."
        case .resolutionNotSupported(let w, let h):
            return "La TV no acepta \(w)x\(h)."
        case .connectionFailed(let reason):
            return "No se pudo conectar con la TV: \(reason)"
        case .unexpectedStatus(let code):
            return "Respuesta inesperada de la TV (HTTP \(code))."
        case .encoderFailed(let reason):
            return "El codificador falló: \(reason)"
        case .audioUnavailable(let reason):
            return "Audio no disponible: \(reason)"
        case .invalidStatus:
            return "La TV devolvió un /status que no se entendió."
        case .malformedResponse:
            return "La TV devolvió una respuesta ilegible."
        }
    }
}
