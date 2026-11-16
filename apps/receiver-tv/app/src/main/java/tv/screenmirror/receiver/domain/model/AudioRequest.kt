package tv.screenmirror.receiver.domain.model

import tv.screenmirror.receiver.core.Protocol

/**
 * Parámetros validados de una sesión de audio (spec: docs/protocol.md).
 */
data class AudioRequest(
    val token: String,
    val sampleRate: Int = Protocol.DEFAULT_SAMPLE_RATE,
    val channels: Int = Protocol.DEFAULT_CHANNELS,
)
