import Foundation

/// Política de reconexión del emisor: backoff y qué fallos merecen reintento.
///
/// Pura y sin dependencias: así se testea sin red ni ScreenCaptureKit.
enum ReconnectPolicy {

    /// Segundos de espera antes del intento `attempt` (1-based): 0.5, 1, 2, 4, 5, 5…
    /// Cap en 5 s: el emisor debe reconectar rápido cuando la TV vuelve del suspensión
    /// sin castigar la red si la TV está apagada (regla: latencia > features).
    static func delaySeconds(forAttempt attempt: Int) -> Double {
        guard attempt >= 1 else { return 0 }
        return min(maxDelaySeconds, 0.5 * pow(2.0, Double(attempt - 1)))
    }

    /// Un error es fatal si reintentar no lo arregla (permiso, token caducado, pantalla ida):
    /// en ese caso la sesión se corta con su mensaje en vez de reintentar para siempre.
    static func isFatal(_ error: Error) -> Bool {
        switch error as? SenderError {
        case .screenRecordingDenied, .unauthorized, .displayNotFound, .pairingRejected:
            return true
        case nil:
            return false
        default:
            return false
        }
    }

    static let maxDelaySeconds = 5.0
}
