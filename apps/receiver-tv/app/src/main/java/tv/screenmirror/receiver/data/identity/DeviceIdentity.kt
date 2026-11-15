package tv.screenmirror.receiver.data.identity

import android.content.Context
import java.util.UUID

/**
 * UUID permanente del dispositivo: el `id` de `/status` y del TXT mDNS.
 * Debe sobrevivir a los reinicios (spec: `id=<uuid-permanente>`), así que va
 * a SharedPreferences en cuanto se crea.
 */
class DeviceIdentity(context: Context) {

    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    val id: String = prefs.getString(KEY_ID, null)
        ?: UUID.randomUUID().toString().also { fresh ->
            prefs.edit().putString(KEY_ID, fresh).apply()
        }

    companion object {
        private const val PREFS_NAME = "device_identity"
        private const val KEY_ID = "id"
    }
}
