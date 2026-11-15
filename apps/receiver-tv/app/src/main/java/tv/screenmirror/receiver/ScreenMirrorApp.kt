package tv.screenmirror.receiver

import android.app.Application
import tv.screenmirror.receiver.core.ReceiverContainer

class ScreenMirrorApp : Application() {
    val container: ReceiverContainer by lazy { ReceiverContainer(this) }
}
