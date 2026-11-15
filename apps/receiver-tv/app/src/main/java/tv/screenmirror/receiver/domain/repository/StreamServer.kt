package tv.screenmirror.receiver.domain.repository

import kotlinx.coroutines.flow.StateFlow
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.StreamRequest

interface StreamServer {
    /** Solicitud de stream activa, o null si nadie está emitiendo. */
    val activeRequest: StateFlow<StreamRequest?>

    /** Fallo irrecuperable del servidor (p. ej. puerto ocupado). */
    val failure: StateFlow<ReceiverError?>

    fun start()

    fun stop()
}
