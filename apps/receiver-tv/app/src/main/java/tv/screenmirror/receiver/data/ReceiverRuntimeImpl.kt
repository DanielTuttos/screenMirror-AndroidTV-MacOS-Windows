package tv.screenmirror.receiver.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import tv.screenmirror.receiver.core.stream.VideoPipeline
import tv.screenmirror.receiver.domain.discovery.DiscoveryAdvertiser
import tv.screenmirror.receiver.domain.model.ReceiverState
import tv.screenmirror.receiver.domain.repository.PairingRepository
import tv.screenmirror.receiver.domain.repository.StreamServer
import tv.screenmirror.receiver.domain.runtime.ReceiverRuntime
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Combina servidor + pipeline + emparejamiento en un único estado para la UI.
 */
class ReceiverRuntimeImpl(
    private val pairing: PairingRepository,
    private val streamServer: StreamServer,
    private val pipeline: VideoPipeline,
    private val advertiser: DiscoveryAdvertiser,
) : ReceiverRuntime {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val started = AtomicBoolean(false)
    private var collectJob: Job? = null

    private val _state = MutableStateFlow<ReceiverState>(ReceiverState.Starting)
    override val state: StateFlow<ReceiverState> = _state.asStateFlow()

    override fun start() {
        if (!started.compareAndSet(false, true)) return

        streamServer.start()
        advertiser.start()
        collectJob?.cancel()
        collectJob = scope.launch {
            combine(
                streamServer.activeRequest,
                pipeline.stats,
                streamServer.failure,
            ) { activeRequest, stats, failure ->
                when {
                    failure != null -> ReceiverState.Stopped(failure.message)
                    activeRequest != null -> ReceiverState.Streaming(stats)
                    else -> ReceiverState.Ready(pairing.currentPin())
                }
            }.collect { _state.value = it }
        }
    }

    override fun stop() {
        if (!started.compareAndSet(true, false)) return
        collectJob?.cancel()
        advertiser.stop()
        streamServer.stop()
        _state.value = ReceiverState.Stopped("detenido")
    }
}
