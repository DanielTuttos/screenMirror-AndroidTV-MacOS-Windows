package tv.screenmirror.receiver.domain.model

/**
 * Solicitud válida de apertura de stream (tras pasar el parser del protocolo).
 */
data class StreamRequest(
    val token: String,
    val width: Int,
    val height: Int,
    val fps: Int,
    val keyint: Int,
    val bitrateKbps: Int,
)
