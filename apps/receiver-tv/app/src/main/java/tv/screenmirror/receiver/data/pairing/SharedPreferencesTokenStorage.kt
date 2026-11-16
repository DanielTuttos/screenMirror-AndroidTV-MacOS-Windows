package tv.screenmirror.receiver.data.pairing

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Persiste los tokens en SharedPreferences para que sobrevivan a la muerte del proceso.
 *
 * Formato: JSON `{token: caducidad}` en un único string (los tokens son pocos:
 * uno por emisor emparejado, TTL 24 h).
 */
class SharedPreferencesTokenStorage(context: Context) : TokenStorage {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun load(): Map<String, Long> {
        val raw = prefs.getString(KEY_TOKENS, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            buildMap {
                for (key in json.keys()) {
                    put(key, json.getLong(key))
                }
            }
        } catch (e: Exception) {
            // Almacenamiento corrupto: mejor empezar de cero que quedarse sin emparejar.
            emptyMap()
        }
    }

    override fun save(tokens: Map<String, Long>) {
        val json = JSONObject()
        tokens.forEach { (token, expiry) -> json.put(token, expiry) }
        prefs.edit().putString(KEY_TOKENS, json.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "screenmirror_pairing"
        private const val KEY_TOKENS = "tokens"
    }
}
