package tv.screenmirror.receiver.core

import android.view.Surface

/**
 * Punto único donde la UI publica la Surface del vídeo cuando está disponible
 * y la retira al destruirse. El pipeline la lee antes de configurar el decoder.
 */
class VideoSurface {
    @Volatile
    var surface: Surface? = null
}
