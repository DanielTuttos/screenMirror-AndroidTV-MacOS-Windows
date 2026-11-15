package tv.screenmirror.receiver.data.http

import java.io.InputStream

/**
 * Corta el flujo tras [limit] bytes: así un cuerpo con Content-Length
 * termina en EOF inmediato en lugar de dejar al lector esperando
 * hasta que el emisor cierre la conexión.
 */
internal class LimitedInputStream(
    private val source: InputStream,
    private val limit: Long,
) : InputStream() {

    private var remaining = limit

    override fun read(): Int {
        if (remaining <= 0) return -1
        val value = source.read()
        if (value >= 0) remaining--
        return value
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (remaining <= 0) return -1
        if (len == 0) return 0
        val toRead = minOf(len.toLong(), remaining).toInt()
        val read = source.read(b, off, toRead)
        if (read > 0) remaining -= read
        return read
    }
}
