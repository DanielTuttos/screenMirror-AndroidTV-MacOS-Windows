package tv.screenmirror.receiver.domain.model

/**
 * Métricas de la sesión de emisión en curso (se actualizan ~1 vez por segundo).
 */
data class StreamStats(
    val bitrateKbps: Int = 0,
    val fps: Int = 0,
    val frames: Long = 0,
    val droppedFrames: Long = 0,
    val bytes: Long = 0,
)
