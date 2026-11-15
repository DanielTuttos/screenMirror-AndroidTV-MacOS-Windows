package tv.screenmirror.receiver.data.pairing

import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.repository.PairingRepository
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * PIN de 6 dígitos por sesión + tokens con caducidad, con rate limit por ventana.
 * El reloj se inyecta para poder testear la caducidad sin esperar.
 */
class PairingStore(
    private val now: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
) : PairingRepository {

    private val pin: String = randomPin()
    private val tokens = ConcurrentHashMap<String, Long>() // token -> fecha de caducidad
    private val attempts = ConcurrentLinkedQueue<Long>()

    override fun currentPin(): String = pin

    override fun pair(pinInput: String): Outcome<String> {
        if (tooManyAttempts()) return Outcome.Failure(ReceiverError.RateLimited)

        attempts.add(now())
        // Comparación en tiempo constante para no filtrar el PIN por tiempos de respuesta.
        if (!MessageDigest.isEqual(pin.toByteArray(), pinInput.toByteArray())) {
            return Outcome.Failure(ReceiverError.InvalidPin)
        }

        pruneExpiredTokens()
        val token = randomToken()
        tokens[token] = now() + Protocol.TOKEN_TTL_MS
        return Outcome.Success(token)
    }

    override fun isValidToken(token: String?): Boolean {
        if (token.isNullOrEmpty()) return false
        val expiry = tokens[token] ?: return false
        if (now() > expiry) {
            tokens.remove(token)
            return false
        }
        return true
    }

    override fun activeTokenCount(): Int {
        pruneExpiredTokens()
        return tokens.size
    }

    private fun tooManyAttempts(): Boolean {
        val windowStart = now() - Protocol.PAIR_WINDOW_MS
        while (attempts.peek()?.let { it < windowStart } == true) attempts.poll()
        return attempts.size >= Protocol.PAIR_MAX_ATTEMPTS
    }

    private fun pruneExpiredTokens() {
        val currentTime = now()
        tokens.entries.removeIf { it.value < currentTime }
    }

    private fun randomPin(): String = "%06d".format(random.nextInt(1_000_000))

    private fun randomToken(): String {
        val bytes = ByteArray(Protocol.TOKEN_BYTES)
        random.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
