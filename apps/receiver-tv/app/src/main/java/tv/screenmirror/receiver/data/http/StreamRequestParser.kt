package tv.screenmirror.receiver.data.http

import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.StreamRequest
import java.net.URLDecoder

/**
 * Parsing de la query string del protocolo. Sin Android: testeable en JVM puro.
 */
object StreamRequestParser {

    fun parse(rawQuery: String?): Outcome<StreamRequest> {
        val params = queryParams(rawQuery)

        val version = params["v"]?.toIntOrNull()
        if (version != null && version != Protocol.VERSION) {
            return Outcome.Failure(ReceiverError.ProtocolMismatch)
        }

        val token = params["token"]?.takeIf { it.isNotBlank() }
            ?: return Outcome.Failure(ReceiverError.InvalidRequest("falta token"))
        val width = params["w"]?.toIntOrNull()
            ?: return Outcome.Failure(ReceiverError.InvalidRequest("falta w"))
        val height = params["h"]?.toIntOrNull()
            ?: return Outcome.Failure(ReceiverError.InvalidRequest("falta h"))

        if (width !in Protocol.MIN_WIDTH..Protocol.MAX_WIDTH ||
            height !in Protocol.MIN_HEIGHT..Protocol.MAX_HEIGHT
        ) {
            return Outcome.Failure(ReceiverError.ResolutionNotSupported)
        }

        val fps = params["fps"]?.toIntOrNull() ?: Protocol.DEFAULT_FPS
        val keyint = params["keyint"]?.toIntOrNull() ?: Protocol.DEFAULT_KEYINT
        val bitrate = params["br"]?.toIntOrNull() ?: Protocol.DEFAULT_BITRATE_KBPS

        if (fps !in 1..120) return Outcome.Failure(ReceiverError.InvalidRequest("fps fuera de rango"))
        if (keyint !in 1..600) return Outcome.Failure(ReceiverError.InvalidRequest("keyint fuera de rango"))
        if (bitrate !in 500..100_000) return Outcome.Failure(ReceiverError.InvalidRequest("br fuera de rango"))

        return Outcome.Success(
            StreamRequest(
                token = token,
                width = width,
                height = height,
                fps = fps,
                keyint = keyint,
                bitrateKbps = bitrate,
            ),
        )
    }

    fun queryParams(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrBlank()) return emptyMap()
        return rawQuery.split('&')
            .filter { it.isNotEmpty() }
            .associate { pair ->
                val separator = pair.indexOf('=')
                if (separator < 0) decode(pair) to ""
                else decode(pair.take(separator)) to decode(pair.substring(separator + 1))
            }
    }

    private fun decode(value: String): String = try {
        URLDecoder.decode(value, "UTF-8")
    } catch (e: Exception) {
        value // entrada malformada: la tratamos literal en lugar de fallar
    }
}
