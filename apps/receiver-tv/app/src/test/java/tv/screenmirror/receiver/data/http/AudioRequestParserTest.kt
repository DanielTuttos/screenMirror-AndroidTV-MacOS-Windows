package tv.screenmirror.receiver.data.http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.AudioRequest

class AudioRequestParserTest {

    @Test
    fun `parsea una query completa`() {
        val result = AudioRequestParser.parse("token=abc123&sr=48000&ch=2")

        assertTrue(result is Outcome.Success)
        assertEquals(AudioRequest("abc123", 48_000, 2), (result as Outcome.Success).value)
    }

    @Test
    fun `aplica valores por defecto cuando faltan opcionales`() {
        val request = AudioRequestParser.parse("token=abc") as Outcome.Success

        assertEquals(48_000, request.value.sampleRate)
        assertEquals(2, request.value.channels)
    }

    @Test
    fun `acepta 44100 mono`() {
        val result = AudioRequestParser.parse("token=abc&sr=44100&ch=1")

        assertTrue(result is Outcome.Success)
        assertEquals(AudioRequest("abc", 44_100, 1), (result as Outcome.Success).value)
    }

    @Test
    fun `sin token devuelve InvalidRequest`() {
        val result = AudioRequestParser.parse("sr=48000")

        assertTrue(result is Outcome.Failure)
        assertTrue((result as Outcome.Failure).error is ReceiverError.InvalidRequest)
    }

    @Test
    fun `sample rate no soportado devuelve InvalidRequest`() {
        val result = AudioRequestParser.parse("token=abc&sr=96000")

        assertTrue(result is Outcome.Failure)
        assertTrue((result as Outcome.Failure).error is ReceiverError.InvalidRequest)
    }

    @Test
    fun `canales fuera de rango devuelven InvalidRequest`() {
        val result = AudioRequestParser.parse("token=abc&ch=5")

        assertTrue(result is Outcome.Failure)
        assertTrue((result as Outcome.Failure).error is ReceiverError.InvalidRequest)
    }

    @Test
    fun `version de protocolo desconocida devuelve ProtocolMismatch`() {
        val result = AudioRequestParser.parse("v=9&token=abc")

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.ProtocolMismatch, (result as Outcome.Failure).error)
    }
}
