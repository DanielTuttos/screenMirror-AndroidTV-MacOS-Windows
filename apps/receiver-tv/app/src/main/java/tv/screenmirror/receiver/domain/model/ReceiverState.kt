package tv.screenmirror.receiver.domain.model

/**
 * Estado observable de la TV para la UI.
 */
sealed interface ReceiverState {
    data object Starting : ReceiverState

    /** Esperando emparejar: la UI muestra el PIN. */
    data class Ready(val pin: String) : ReceiverState

    /** Recibiendo vídeo: la UI muestra el HUD de estadísticas. */
    data class Streaming(val stats: StreamStats) : ReceiverState

    data class Stopped(val reason: String) : ReceiverState
}
