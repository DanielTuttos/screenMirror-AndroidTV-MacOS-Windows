package tv.screenmirror.receiver.core

/**
 * ÚNICO punto con las constantes del protocolo v0 (spec: docs/protocol.md).
 * Si cambia el protocolo, se cambia aquí y en Protocol.swift / Protocol.cs.
 */
object Protocol {
    const val VERSION = 0
    const val PORT = 9471

    /// Tipo de servicio mDNS que anuncia el receptor (spec: docs/protocol.md).
    /// NsdManager/ NWBrowser esperan el tipo sin el sufijo `.local`.
    const val SERVICE_TYPE = "_screenmirror._tcp"

    const val PATH_STATUS = "/status"
    const val PATH_PAIR = "/pair"
    const val PATH_STREAM = "/stream"
    const val PATH_AUDIO = "/audio"

    const val CONTENT_TYPE_ANNEXB = "video/avc; annexb"
    const val CONTENT_TYPE_PCM = "audio/pcm"

    const val DEFAULT_FPS = 60
    const val DEFAULT_KEYINT = 120
    const val DEFAULT_BITRATE_KBPS = 8_000

    const val DEFAULT_SAMPLE_RATE = 48000
    const val DEFAULT_CHANNELS = 2
    const val AUDIO_BITS_PER_SAMPLE = 16

    const val MIN_WIDTH = 160
    const val MIN_HEIGHT = 90

    // Techo = resolución de la pantalla extendida del emisor (2560x1440).
    // El panel de la TV es 4K, pero 4K sin medir latencia sería prometer de más.
    const val MAX_WIDTH = 2560
    const val MAX_HEIGHT = 1440

    const val PIN_LENGTH = 6
    const val PAIR_MAX_ATTEMPTS = 5
    const val PAIR_WINDOW_MS = 60_000L
    const val TOKEN_TTL_MS = 24 * 60 * 60 * 1000L
    const val TOKEN_BYTES = 32
}