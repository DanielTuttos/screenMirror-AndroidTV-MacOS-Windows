package tv.screenmirror.receiver.data.http

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException

class ChunkedInputStreamTest {

    @Test
    fun `desenmascara varios chunks`() {
        val wire = "5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n".toByteArray()

        val payload = ChunkedInputStream(ByteArrayInputStream(wire)).readBytes()

        assertArrayEquals("Hello World".toByteArray(), payload)
    }

    @Test
    fun `tolera extensiones en la cabecera de chunk`() {
        val wire = "4;foo=bar\r\nABCD\r\n0\r\n\r\n".toByteArray()

        val payload = ChunkedInputStream(ByteArrayInputStream(wire)).readBytes()

        assertArrayEquals("ABCD".toByteArray(), payload)
    }

    @Test
    fun `devuelve -1 tras el chunk final`() {
        val stream = ChunkedInputStream(ByteArrayInputStream("0\r\n\r\n".toByteArray()))

        assertTrue(stream.read() < 0)
    }

    @Test(expected = IOException::class)
    fun `lanza error si el chunk esta truncado`() {
        val wire = "10\r\ncortado".toByteArray()

        ChunkedInputStream(ByteArrayInputStream(wire)).readBytes()
    }
}
