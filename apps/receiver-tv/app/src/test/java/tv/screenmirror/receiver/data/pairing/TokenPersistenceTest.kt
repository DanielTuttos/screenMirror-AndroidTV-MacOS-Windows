package tv.screenmirror.receiver.data.pairing

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import tv.screenmirror.receiver.domain.Outcome

class TokenPersistenceTest {

    @Test
    fun `un token emitido sobrevive a un reinicio del proceso con el mismo storage`() {
        val storage = InMemoryTokenStorage()
        val firstBoot = PairingStore(storage = storage)
        val token = (firstBoot.pair(firstBoot.currentPin()) as Outcome.Success).value

        // La TV mata el proceso y arranca otra instancia con el mismo almacenamiento.
        val secondBoot = PairingStore(storage = storage)

        assertTrue(secondBoot.isValidToken(token))
    }

    @Test
    fun `sin storage compartido el token no sobrevive`() {
        val firstBoot = PairingStore()
        val token = (firstBoot.pair(firstBoot.currentPin()) as Outcome.Success).value

        val secondBoot = PairingStore()

        assertFalse(secondBoot.isValidToken(token))
    }

    @Test
    fun `un token caducado no se recarga en el arranque`() {
        var clock = 0L
        val storage = InMemoryTokenStorage()
        val firstBoot = PairingStore(now = { clock }, storage = storage)
        val token = (firstBoot.pair(firstBoot.currentPin()) as Outcome.Success).value

        // Reinicio pasadas más de 24 h (TTL del token).
        clock = 25 * 60 * 60 * 1000L
        val secondBoot = PairingStore(now = { clock }, storage = storage)

        assertFalse(secondBoot.isValidToken(token))
    }

    @Test
    fun `el storage guarda el token emitido con su caducidad`() {
        val storage = InMemoryTokenStorage()
        val store = PairingStore(storage = storage)
        val token = (store.pair(store.currentPin()) as Outcome.Success).value

        val saved = storage.load()
        assertTrue(saved.containsKey(token))
        // Caducidad = ahora + TTL (24 h).
        assertTrue(saved.getValue(token) >= 24 * 60 * 60 * 1000L)
    }
}
