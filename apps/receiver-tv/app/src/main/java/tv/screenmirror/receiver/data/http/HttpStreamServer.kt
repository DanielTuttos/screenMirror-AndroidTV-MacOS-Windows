package tv.screenmirror.receiver.data.http

import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONException
import org.json.JSONObject
import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.core.stream.AnnexBAccessUnitReader
import tv.screenmirror.receiver.core.stream.VideoPipeline
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.StreamRequest
import tv.screenmirror.receiver.domain.repository.PairingRepository
import tv.screenmirror.receiver.domain.repository.StreamServer
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Servidor HTTP mínimo del protocolo v0 (sin frameworks).
 * Un stream a la vez; el cuerpo (H.264 Annex-B) va directo al pipeline de vídeo.
 */
class HttpStreamServer(
    private val pairing: PairingRepository,
    private val pipeline: VideoPipeline,
    private val receiverId: String = UUID.randomUUID().toString(),
    private val port: Int = Protocol.PORT,
) : StreamServer {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val started = AtomicBoolean(false)
    private val streaming = AtomicBoolean(false)

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    private var activeStreamSocket: Socket? = null

    private val _activeRequest = MutableStateFlow<StreamRequest?>(null)
    override val activeRequest: StateFlow<StreamRequest?> = _activeRequest.asStateFlow()

    private val _failure = MutableStateFlow<ReceiverError?>(null)
    override val failure: StateFlow<ReceiverError?> = _failure.asStateFlow()

    override fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            val server = ServerSocket()
            try {
                server.reuseAddress = true
                server.bind(InetSocketAddress(port))
                serverSocket = server
                Log.i(TAG, "Escuchando en el puerto $port")
                while (started.get() && !server.isClosed) {
                    val client = server.accept()
                    scope.launch { serve(client) }
                }
            } catch (e: IOException) {
                if (started.get()) {
                    Log.e(TAG, "No se pudo escuchar en el puerto $port", e)
                    _failure.value = ReceiverError.ServiceFailure("puerto $port no disponible")
                } else {
                    Log.i(TAG, "Servidor detenido")
                }
            } finally {
                runCatching { server.close() }
            }
        }
    }

    override fun stop() {
        started.set(false)
        runCatching { activeStreamSocket?.close() }
        runCatching { serverSocket?.close() }
    }

    private fun serve(client: Socket) {
        client.use { socket ->
            socket.soTimeout = HEADER_TIMEOUT_MS
            val input = socket.getInputStream().buffered()
            val output = socket.getOutputStream()

            val request = HttpRequestParser.read(input)
            if (request == null) {
                HttpResponse.error(output, ReceiverError.InvalidRequest("cabeceras inválidas"))
                return
            }

            try {
                route(request, input, output, socket)
            } catch (e: IOException) {
                Log.w(TAG, "Conexión interrumpida en ${request.method} ${request.path}: ${e.message}")
            } catch (e: Exception) {
                Log.e(TAG, "Error al atender ${request.method} ${request.path}", e)
                // Si el stream ya respondió 200, este write falla y se ignora a propósito.
                runCatching { HttpResponse.error(output, ReceiverError.InternalError) }
            }
        }
    }

    private fun route(request: HttpRequest, input: InputStream, output: OutputStream, socket: Socket) {
        when {
            request.method == "GET" && request.path == Protocol.PATH_STATUS ->
                HttpResponse.json(output, 200, statusJson())

            request.method == "POST" && request.path == Protocol.PATH_PAIR ->
                handlePair(request, input, output)

            request.method == "POST" && request.path == Protocol.PATH_STREAM ->
                handleStream(request, input, output, socket)

            request.method == "DELETE" && request.path == Protocol.PATH_STREAM ->
                handleDelete(request, output)

            else ->
                HttpResponse.error(output, ReceiverError.NotFound)
        }
    }

    private fun handlePair(request: HttpRequest, input: InputStream, output: OutputStream) {
        expect100Continue(request, output)

        val body = HttpRequestParser.readBody(input, request.contentLength)
            ?: return HttpResponse.error(output, ReceiverError.InvalidRequest("cuerpo ausente o demasiado grande"))

        val pin = try {
            JSONObject(String(body, Charsets.UTF_8)).optString("pin")
        } catch (e: JSONException) {
            return HttpResponse.error(output, ReceiverError.InvalidRequest("json inválido"))
        }

        when (val result = pairing.pair(pin)) {
            is Outcome.Success ->
                HttpResponse.json(output, 200, """{"token":"${result.value}","ttl":${Protocol.TOKEN_TTL_MS / 1000}}""")

            is Outcome.Failure ->
                HttpResponse.error(output, result.error)
        }
    }

    private fun handleStream(request: HttpRequest, input: InputStream, output: OutputStream, socket: Socket) {
        expect100Continue(request, output)

        val parsed = when (val result = StreamRequestParser.parse(request.query)) {
            is Outcome.Failure -> return HttpResponse.error(output, result.error)
            is Outcome.Success -> result.value
        }
        if (!pairing.isValidToken(parsed.token)) {
            return HttpResponse.error(output, ReceiverError.InvalidToken)
        }
        if (!streaming.compareAndSet(false, true)) {
            return HttpResponse.error(output, ReceiverError.StreamBusy)
        }

        when (val startedPipeline = pipeline.start(parsed)) {
            is Outcome.Failure -> {
                streaming.set(false)
                return HttpResponse.error(output, startedPipeline.error)
            }
            is Outcome.Success -> Unit
        }

        try {
            HttpResponse.streamOk(output)
            _activeRequest.value = parsed
            activeStreamSocket = socket
            pump(request, input, socket)
        } finally {
            activeStreamSocket = null
            _activeRequest.value = null
            streaming.set(false)
            pipeline.stop()
        }
    }

    /**
     * Lee el cuerpo y lo alimenta al pipeline hasta que:
     * el emisor corta, el pipeline muere, el stream se cancela o pasa un minuto sin datos.
     */
    private fun pump(request: HttpRequest, input: InputStream, socket: Socket) {
        // Chunked (ffmpeg) o Content-Length (curl): ambos llegan a EOF sin esperar a que el emisor cierre.
        val body: InputStream = when {
            request.isChunked -> ChunkedInputStream(input)
            request.contentLength > 0 -> LimitedInputStream(input, request.contentLength.toLong())
            else -> input
        }
        socket.soTimeout = IDLE_TIMEOUT_MS

        val reader = AnnexBAccessUnitReader()
        val buffer = ByteArray(READ_BUFFER_BYTES)
        var idleReads = 0

        while (pipeline.isRunning()) {
            val read = try {
                body.read(buffer)
            } catch (e: SocketTimeoutException) {
                idleReads++
                if (idleReads >= MAX_IDLE_READS) {
                    Log.w(TAG, "Emisor inactivo durante ${MAX_IDLE_READS * IDLE_TIMEOUT_MS / 1000}s: cierro el stream")
                    break
                }
                continue
            }
            idleReads = 0
            if (read < 0) break

            for (accessUnit in reader.feed(buffer, read)) {
                pipeline.feedAccessUnit(accessUnit)
            }
        }
    }

    private fun handleDelete(request: HttpRequest, output: OutputStream) {
        val token = StreamRequestParser.queryParams(request.query)["token"]
        if (!pairing.isValidToken(token)) {
            return HttpResponse.error(output, ReceiverError.InvalidToken)
        }
        // Cerrar el socket despierta al hilo de pump, que verá EOF y terminará.
        runCatching { activeStreamSocket?.close() }
        HttpResponse.status(output, 204)
    }

    private fun expect100Continue(request: HttpRequest, output: OutputStream) {
        if (request.headers["expect"]?.contains("100-continue", ignoreCase = true) != true) return
        output.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.US_ASCII))
        output.flush()
    }

    private fun statusJson(): String = JSONObject()
        .put("app", "ScreenMirror Receiver")
        .put("proto", Protocol.VERSION)
        .put("name", Build.MODEL)
        .put("id", receiverId)
        .put("maxW", Protocol.MAX_WIDTH)
        .put("maxH", Protocol.MAX_HEIGHT)
        .put("codec", "h264")
        .put("busy", streaming.get())
        .toString()

    companion object {
        private const val TAG = "HttpStreamServer"
        private const val HEADER_TIMEOUT_MS = 10_000
        private const val IDLE_TIMEOUT_MS = 5_000
        private const val MAX_IDLE_READS = 6
        private const val READ_BUFFER_BYTES = 64 * 1024
    }
}
