package tv.screenmirror.receiver.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import android.view.Surface
import kotlinx.coroutines.flow.StateFlow
import tv.screenmirror.receiver.ScreenMirrorApp
import tv.screenmirror.receiver.core.ReceiverContainer
import tv.screenmirror.receiver.domain.model.ReceiverState

class ReceiverViewModel(private val container: ReceiverContainer) : ViewModel() {

    val state: StateFlow<ReceiverState> = container.runtime.state

    init {
        // Arranque redundante con el servicio: si el servicio tarda, la UI ya funciona.
        container.runtime.start()
    }

    fun onSurfaceChanged(surface: Surface?) {
        container.videoSurface.surface = surface
    }

    companion object {
        val Factory = viewModelFactory {
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as ScreenMirrorApp
                ReceiverViewModel(app.container)
            }
        }
    }
}
