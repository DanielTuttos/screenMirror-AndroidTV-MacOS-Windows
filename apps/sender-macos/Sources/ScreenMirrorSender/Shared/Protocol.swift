import Foundation

/// ÚNICO punto con las constantes del protocolo v0 (spec: docs/protocol.md).
/// Si cambia el protocolo, se cambia aquí y en Protocol.kt / Protocol.cs.
enum Protocol {
    static let version = 0
    static let port: UInt16 = 9471

    /// Tipo de servicio que anuncia el receptor por mDNS (spec: docs/protocol.md).
    static let serviceType = "_screenmirror._tcp"

    static let pathStatus = "/status"
    static let pathPair = "/pair"
    static let pathStream = "/stream"
    static let pathAudio = "/audio"

    static let contentTypeAnnexB = "video/avc; annexb"
    static let contentTypePcm = "audio/pcm"

    static let defaultFps = 30
    static let defaultKeyint = 60
    static let defaultBitrateKbps = 8_000

    static let defaultSampleRate = 48000
    static let defaultChannels = 2
    static let audioBitsPerSample = 16

    static let pinLength = 6
}
