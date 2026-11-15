import Foundation

/// Configuración de un stream: los query params de `POST /stream` (docs/protocol.md).
/// Modelo puro: sin ScreenCaptureKit ni VideoToolbox, testeable en XCTest.
struct StreamConfig: Equatable {
    var width: Int
    var height: Int
    var fps: Int = Protocol.defaultFps
    var keyint: Int = Protocol.defaultKeyint
    var bitrateKbps: Int = Protocol.defaultBitrateKbps

    /// Reduce la resolución manteniendo la proporción hasta encajar en el techo del receptor.
    /// El emisor nunca escala hacia arriba: el receptor responde `413` por encima de su máximo.
    func fitted(maxWidth: Int, maxHeight: Int) -> StreamConfig {
        guard width > 0, height > 0, maxWidth > 0, maxHeight > 0 else { return self }
        let scale = min(Double(maxWidth) / Double(width), Double(maxHeight) / Double(height), 1.0)
        guard scale < 1.0 else { return self }

        var result = self
        // El chroma 4:2:0 exige dimensiones pares: si no, VideoToolbox y el decoder de la TV se quejan.
        result.width = even(Int(Double(width) * scale))
        result.height = even(Int(Double(height) * scale))
        return result
    }

    /// Bitrate proporcional a los píxeles: 8 Mbps @1080p es la referencia validada en fase 1.
    /// Sin esto, texto fino a 1440p sale borroso (el script de prueba hace lo mismo).
    static func bitrateKbps(forWidth width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return Protocol.defaultBitrateKbps }
        let scaled = Protocol.defaultBitrateKbps * width * height / (1920 * 1080)
        return max(500, scaled)
    }

    /// Query string del stream, sin el token (ese va primero y lo aporta la sesión de emparejamiento).
    func query(token: String) -> String {
        "token=\(token)&w=\(width)&h=\(height)&fps=\(fps)&keyint=\(keyint)&br=\(bitrateKbps)"
    }

    private func even(_ value: Int) -> Int {
        let clamped = max(2, value)
        return clamped - clamped % 2
    }
}
