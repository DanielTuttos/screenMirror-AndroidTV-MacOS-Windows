package tv.screenmirror.receiver.data.http

import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.AudioRequest

/**
 * Parsing de la query string de `POST /audio` (spec: docs/protocol.md). Sin Android: testeable en JVM puro.
 */
object AudioRequestParser {

    private val SUPPORTED_SAMPLE_RATES = setOf(44_100, 48_000)

    fun parse(rawQuery: String?): Outcome<AudioRequest> {
        val params = StreamRequestParser.queryParams(rawQuery)

        val version = params["v"]?.toIntOrNull()
        if (version != null && version != Protocol.VERSION) {
            return Outcome.Failure(ReceiverError.ProtocolMismatch)
        }

        val token = params["token"]?.takeIf { it.isNotBlank() }
            ?: return Outcome.Failure(ReceiverError.InvalidRequest("falta token"))
        val sampleRate = params["sr"]?.toIntOrNull() ?: Protocol.DEFAULT_SAMPLE_RATE
        val channels = params["ch"]?.toIntOrNull() ?: Protocol.DEFAULT_CHANNELS

        if (sampleRate !in SUPPORTED_SAMPLE_RATES) {
            return Outcome.Failure(ReceiverError.InvalidRequest("sr no soportado"))
        }
        if (channels !in 1..2) {
            return Outcome.Failure(ReceiverError.InvalidRequest("ch fuera de rango"))
        }

        return Outcome.Success(
            AudioRequest(token = token, sampleRate = sampleRate, channels = channels),
        )
    }
}
