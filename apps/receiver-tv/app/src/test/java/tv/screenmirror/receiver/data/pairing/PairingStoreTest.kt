package tv.screenmirror.receiver.data.pairing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import java.security.SecureRandom

class PairingStoreTest {

    private var clock = 0L
    private val store = PairingStore(now = { clock }, random = SecureRandom())

    @Test
    fun `pair con el PIN correcto devuelve un token hex de 256 bits`() {
        val result = store.pair(store.currentPin())

        assertTrue(result is Outcome.Success)
        val token = (result as Outcome.Success).value
        assertEquals(Protocol.TOKEN_BYTES * 2, token.length)
        assertTrue(token.all { it in '0'..'9' || it in 'a'..'f' })
        assertTrue(store.isValidToken(token))
        assertEquals(1, store.activeTokenCount())
    }

    @Test
    fun `PIN incorrecto devuelve InvalidPin`() {
        val result = store.pair(wrongPin())

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.InvalidPin, (result as Outcome.Failure).error)
        assertFalse(store.isValidToken(null))
    }

    @Test
    fun `tras 5 intentos se bloquea aunque el PIN sea correcto`() {
        repeat(Protocol.PAIR_MAX_ATTEMPTS) { store.pair(wrongPin()) }

        val result = store.pair(store.currentPin())

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.RateLimited, (result as Outcome.Failure).error)
    }

    @Test
    fun `el bloqueo se levanta al pasar la ventana de tiempo`() {
        repeat(Protocol.PAIR_MAX_ATTEMPTS) { store.pair(wrongPin()) }
        clock += Protocol.PAIR_WINDOW_MS + 1

        assertTrue(store.pair(store.currentPin()) is Outcome.Success)
    }

    @Test
    fun `el token caduca segun el reloj`() {
        val token = (store.pair(store.currentPin()) as Outcome.Success).value

        clock += Protocol.TOKEN_TTL_MS + 1

        assertFalse(store.isValidToken(token))
        assertEquals(0, store.activeTokenCount())
    }

    @Test
    fun `token nulo o basura nunca es valido`() {
        assertFalse(store.isValidToken(null))
        assertFalse(store.isValidToken(""))
        assertFalse(store.isValidToken("no-existe"))
    }

    private fun wrongPin(): String =
        if (store.currentPin() != "000000") "000000" else "111111"
}
