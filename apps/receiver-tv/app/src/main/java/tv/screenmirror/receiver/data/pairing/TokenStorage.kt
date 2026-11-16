package tv.screenmirror.receiver.data.pairing

/**
 * Persistencia de los tokens de sesión emparejados.
 *
 * Se inyecta en [PairingStore] para que la TV pueda matar el proceso del receptor
 * (o reiniciarse) sin perder los tokens: si no, el emisor recibiría 401 al reconectar.
 */
interface TokenStorage {
    /** token -> fecha de caducidad (ms). */
    fun load(): Map<String, Long>
    fun save(tokens: Map<String, Long>)
}

/** Solo memoria: pierde los tokens al reiniciar (por defecto y en tests JVM). */
class InMemoryTokenStorage : TokenStorage {
    private var stored: Map<String, Long> = emptyMap()

    override fun load(): Map<String, Long> = stored
    override fun save(tokens: Map<String, Long>) {
        stored = tokens.toMap()
    }
}
