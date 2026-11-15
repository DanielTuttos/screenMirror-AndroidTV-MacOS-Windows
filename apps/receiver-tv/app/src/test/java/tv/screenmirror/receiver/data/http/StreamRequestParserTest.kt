package tv.screenmirror.receiver.data.http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.StreamRequest

class StreamRequestParserTest {

    @Test
    fun `parsea una query completa`() {
        val result = StreamRequestParser.parse("token=abc123&w=1280&h=720&fps=30&keyint=60&br=8000")

        assertTrue(result is Outcome.Success)
        val request = (result as Outcome.Success).value
        assertEquals(StreamRequest("abc123", 1280, 720, 30, 60, 8000), request)
    }

    @Test
    fun `aplica valores por defecto cuando faltan opcionales`() {
        val request = StreamRequestParser.parse("token=abc&w=640&h=360") as Outcome.Success

        assertEquals(30, request.value.fps)
        assertEquals(60, request.value.keyint)
        assertEquals(8_000, request.value.bitrateKbps)
    }

    @Test
    fun `sin token devuelve InvalidRequest`() {
        val result = StreamRequestParser.parse("w=640&h=360")

        assertTrue(result is Outcome.Failure)
        assertTrue((result as Outcome.Failure).error is ReceiverError.InvalidRequest)
    }

    @Test
    fun `resolucion por encima del maximo devuelve ResolutionNotSupported`() {
        val result = StreamRequestParser.parse("token=abc&w=3840&h=2160")

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.ResolutionNotSupported, (result as Outcome.Failure).error)
    }

    @Test
    fun `acepta la resolucion maxima de la pantalla extendida`() {
        val result = StreamRequestParser.parse("token=abc&w=2560&h=1440")

        assertTrue(result is Outcome.Success)
        assertEquals(2560, (result as Outcome.Success).value.width)
        assertEquals(1440, result.value.height)
    }

    @Test
    fun `un pixel por encima del maximo devuelve ResolutionNotSupported`() {
        val result = StreamRequestParser.parse("token=abc&w=2561&h=1440")

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.ResolutionNotSupported, (result as Outcome.Failure).error)
    }

    @Test
    fun `version de protocolo desconocida devuelve ProtocolMismatch`() {
        val result = StreamRequestParser.parse("v=9&token=abc&w=640&h=360")

        assertTrue(result is Outcome.Failure)
        assertEquals(ReceiverError.ProtocolMismatch, (result as Outcome.Failure).error)
    }

    @Test
    fun `valores fuera de rango devuelven InvalidRequest`() {
        val result = StreamRequestParser.parse("token=abc&w=640&h=360&fps=999")

        assertTrue(result is Outcome.Failure)
        assertTrue((result as Outcome.Failure).error is ReceiverError.InvalidRequest)
    }

    @Test
    fun `query nula o vacia produce mapa vacio`() {
        assertTrue(StreamRequestParser.queryParams(null).isEmpty())
        assertTrue(StreamRequestParser.queryParams("").isEmpty())
    }

    @Test
    fun `decodifica valores percent-encoded`() {
        val params = StreamRequestParser.queryParams("token=a%20b&name=TV%20Salon")

        assertEquals("a b", params["token"])
        assertEquals("TV Salon", params["name"])
    }
}
