package tv.screenmirror.receiver.data.http

import java.io.IOException
import java.io.InputStream

/**
 * Desenmascara el cuerpo de una petición HTTP con Transfer-Encoding: chunked
 * (ffmpeg envía el stream así). No conoce nada del protocolo ScreenMirror.
 */
internal class ChunkedInputStream(private val source: InputStream) : InputStream() {

    private var remainingInChunk = 0
    private var finished = false

    override fun read(): Int {
        val single = ByteArray(1)
        return read(single, 0, 1).let { if (it < 0) -1 else single[0].toInt() and 0xFF }
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (finished) return -1
        if (len == 0) return 0

        if (remainingInChunk == 0 && !nextChunk()) return -1

        val toRead = minOf(len, remainingInChunk)
        val read = source.read(b, off, toRead)
        if (read < 0) throw IOException("stream truncado dentro de un chunk")

        remainingInChunk -= read
        if (remainingInChunk == 0) consumeCrlf()
        return read
    }

    /** Devuelve false si era el último chunk (0). */
    private fun nextChunk(): Boolean {
        val header = readAsciiLine(source) ?: throw IOException("cabecera de chunk ausente")
        val size = header.substringBefore(';').trim().toIntOrNull(16)
            ?: throw IOException("tamaño de chunk inválido: $header")
        if (size == 0) {
            drainTrailers()
            finished = true
            return false
        }
        remainingInChunk = size
        return true
    }

    private fun consumeCrlf() {
        val carriageReturn = source.read()
        val lineFeed = source.read()
        if (carriageReturn != '\r'.code || lineFeed != '\n'.code) {
            throw IOException("fin de chunk sin CRLF")
        }
    }

    private fun drainTrailers() {
        while (true) {
            val line = readAsciiLine(source) ?: return
            if (line.isEmpty()) return
        }
    }
}
