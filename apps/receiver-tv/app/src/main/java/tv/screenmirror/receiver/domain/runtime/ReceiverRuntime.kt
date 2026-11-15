package tv.screenmirror.receiver.domain.runtime

import kotlinx.coroutines.flow.StateFlow
import tv.screenmirror.receiver.domain.model.ReceiverState

/**
 * Fachada que usan la UI y el servicio: estado global del receptor.
 */
interface ReceiverRuntime {
    val state: StateFlow<ReceiverState>

    fun start()

    fun stop()
}
