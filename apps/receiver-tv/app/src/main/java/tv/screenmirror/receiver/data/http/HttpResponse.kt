package tv.screenmirror.receiver.data.http

import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.ReceiverError
import java.io.OutputStream

/**
 * Escritura de respuestas HTTP. Mapeo de errores de dominio -> códigos HTTP (asunto de transporte).
 */
internal object HttpResponse {

    private const val SERVER = "ScreenMirror/0"

    fun json(out: OutputStream, status: Int, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        val head = buildString {
            append("HTTP/1.1 $status ${reasonFor(status)}\r\n")
            append("Content-Type: application/json\r\n")
            append("Content-Length: ${bytes.size}\r\n")
            append("Connection: close\r\n")
            append("Server: $SERVER\r\n")
            append("\r\n")
        }
        out.write(head.toByteArray(Charsets.US_ASCII))
        out.write(bytes)
        out.flush()
    }

    fun status(out: OutputStream, status: Int) {
        val head = "HTTP/1.1 $status ${reasonFor(status)}\r\nConnection: close\r\nServer: $SERVER\r\n\r\n"
        out.write(head.toByteArray(Charsets.US_ASCII))
        out.flush()
    }

    fun error(out: OutputStream, error: ReceiverError) = json(
        out,
        error.httpStatus(),
        """{"error":"${error::class.simpleName}","message":"${error.message}"}""",
    )

    /** Respuesta 200 inicial antes de volcar el flujo H.264 crudo (se cierra al terminar). */
    fun streamOk(out: OutputStream) {
        val head = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: ${Protocol.CONTENT_TYPE_ANNEXB}\r\n" +
            "Connection: close\r\n" +
            "Server: $SERVER\r\n" +
            "\r\n"
        out.write(head.toByteArray(Charsets.US_ASCII))
        out.flush()
    }

    private fun ReceiverError.httpStatus(): Int = when (this) {
        is ReceiverError.InvalidRequest -> 400
        ReceiverError.InvalidPin, ReceiverError.InvalidToken -> 401
        ReceiverError.ProtocolMismatch -> 403
        ReceiverError.NotFound -> 404
        ReceiverError.StreamBusy -> 409
        ReceiverError.ResolutionNotSupported -> 413
        ReceiverError.RateLimited -> 429
        ReceiverError.NoDisplay -> 503
        is ReceiverError.ServiceFailure, ReceiverError.InternalError -> 500
    }

    private fun reasonFor(status: Int): String = when (status) {
        200 -> "OK"
        204 -> "No Content"
        400 -> "Bad Request"
        401 -> "Unauthorized"
        403 -> "Forbidden"
        404 -> "Not Found"
        409 -> "Conflict"
        413 -> "Payload Too Large"
        429 -> "Too Many Requests"
        500 -> "Internal Server Error"
        503 -> "Service Unavailable"
        else -> "OK"
    }
}
