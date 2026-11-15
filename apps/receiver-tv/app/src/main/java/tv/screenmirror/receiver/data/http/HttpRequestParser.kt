package tv.screenmirror.receiver.data.http

import java.io.ByteArrayOutputStream
import java.io.InputStream

internal data class HttpRequest(
    val method: String,
    val path: String,
    val query: String?,
    val headers: Map<String, String>,
    val contentLength: Int,
) {
    val isChunked: Boolean
        get() = headers["transfer-encoding"]?.contains("chunked", ignoreCase = true) == true
}

/**
 * Lectura mínima de peticiones HTTP/1.1 para el protocolo v0.
 */
internal object HttpRequestParser {

    private const val MAX_HEADER_LINES = 100
    private const val MAX_BODY_BYTES = 8 * 1024

    fun read(input: InputStream): HttpRequest? {
        val requestLine = readAsciiLine(input) ?: return null
        val parts = requestLine.split(' ')
        if (parts.size < 2 || parts.size > 3) return null

        val (path, query) = splitTarget(parts[1])
        val headers = mutableMapOf<String, String>()
        var lineCount = 0

        while (true) {
            val line = readAsciiLine(input) ?: return null
            if (line.isEmpty()) break
            if (++lineCount > MAX_HEADER_LINES) return null

            val separator = line.indexOf(':')
            if (separator <= 0) continue // cabecera malformada: la ignoramos
            headers[line.take(separator).trim().lowercase()] = line.drop(separator + 1).trim()
        }

        return HttpRequest(
            method = parts[0].uppercase(),
            path = path,
            query = query,
            headers = headers,
            contentLength = headers["content-length"]?.toIntOrNull() ?: 0,
        )
    }

    fun readBody(input: InputStream, contentLength: Int): ByteArray? {
        if (contentLength <= 0 || contentLength > MAX_BODY_BYTES) return null
        val body = ByteArray(contentLength)
        var offset = 0
        while (offset < contentLength) {
            val read = input.read(body, offset, contentLength - offset)
            if (read < 0) return null
            offset += read
        }
        return body
    }

    private fun splitTarget(target: String): Pair<String, String?> {
        val separator = target.indexOf('?')
        return if (separator < 0) target to null
        else target.take(separator) to target.substring(separator + 1)
    }
}

/** Lee una línea ASCII hasta \n (tolera \r\n). Devuelve null si se corta la conexión o es demasiado larga. */
internal fun readAsciiLine(input: InputStream): String? {
    val bytes = ByteArrayOutputStream()
    while (true) {
        val current = input.read()
        if (current < 0) return null
        if (current == '\n'.code) break
        bytes.write(current)
        if (bytes.size() > MAX_LINE_BYTES) return null
    }
    val line = String(bytes.toByteArray(), Charsets.ISO_8859_1)
    return if (line.endsWith("\r")) line.dropLast(1) else line
}

private const val MAX_LINE_BYTES = 8 * 1024
