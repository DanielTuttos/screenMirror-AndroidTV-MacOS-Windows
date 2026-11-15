package tv.screenmirror.receiver.core.stream

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import tv.screenmirror.receiver.core.VideoSurface
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.StreamRequest
import tv.screenmirror.receiver.domain.model.StreamStats
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Decodifica H.264 con MediaCodec (HW) y lo pinta en la Surface.
 *
 * Hilos:
 *  - red: solo llama a feedAccessUnit() (encola, nunca bloquea)
 *  - codec: hilo dedicado que drena la cola hacia MediaCodec y libera frames
 *
 * "generación" invalida el bucle anterior al reiniciar para que una parada
 * tardía no pueda matar una sesión recién abierta.
 */
class VideoPipeline(private val videoSurface: VideoSurface) {

    private val _stats = MutableStateFlow(StreamStats())
    val stats: StateFlow<StreamStats> = _stats.asStateFlow()

    private val accessUnits = LinkedBlockingDeque<ByteArray>(MAX_PENDING_AUS)
    private val generation = AtomicInteger(0)
    private val running = AtomicBoolean(false)

    private val codecThread = HandlerThread("screenmirror-decoder").apply { start() }
    private val codecHandler = Handler(codecThread.looper)

    // Solo el hilo del codec toca estas variables (totalDropped es atómica por venir de la red).
    private var windowStartMs = 0L
    private var windowBytes = 0L
    private var windowFrames = 0
    private var totalBytes = 0L
    private var totalFrames = 0L
    private val totalDropped = AtomicLong(0)

    fun start(request: StreamRequest): Outcome<Unit> {
        val surface = videoSurface.surface ?: return Outcome.Failure(ReceiverError.NoDisplay)
        if (!running.compareAndSet(false, true)) return Outcome.Failure(ReceiverError.StreamBusy)
        return try {
            val codec = createDecoder(request, surface)
            val myGeneration = generation.incrementAndGet()
            codecHandler.post { codecLoop(codec, myGeneration) }
            Outcome.Success(Unit)
        } catch (e: Exception) {
            running.set(false)
            Log.e(TAG, "No se pudo configurar el decoder", e)
            Outcome.Failure(ReceiverError.InternalError)
        }
    }

    fun feedAccessUnit(accessUnit: ByteArray) {
        if (!running.get()) return
        // Cola llena: preferimos descartar y contar antes que acumular latencia.
        if (!accessUnits.offerLast(accessUnit)) totalDropped.incrementAndGet()
    }

    fun isRunning(): Boolean = running.get()

    fun stop() {
        if (!running.getAndSet(false)) return
        generation.incrementAndGet()
        accessUnits.clear()
    }

    private fun createDecoder(request: StreamRequest, surface: Surface): MediaCodec {
        val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val format = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            request.width,
            request.height,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        }
        codec.configure(format, surface, null, 0)
        return codec
    }

    private fun codecLoop(codec: MediaCodec, myGeneration: Int) {
        val bufferInfo = MediaCodec.BufferInfo()
        var pending: ByteArray? = null
        try {
            codec.start()
            resetWindow()
            while (running.get() && generation.get() == myGeneration) {
                // La Surface se destruyó (app en segundo plano): cortamos el stream.
                if (videoSurface.surface == null) break

                val accessUnit = pending
                    ?: accessUnits.pollFirst(POLL_TIMEOUT_MS, TimeUnit.MILLISECONDS)?.also { pending = it }
                if (accessUnit != null && feedInput(codec, accessUnit)) pending = null

                drainOutput(codec, bufferInfo)
            }
        } catch (e: MediaCodec.CodecException) {
            // El decoder hardware falló (p. ej. perfil no soportado): el mensaje trae el código.
            Log.e(TAG, "Decoder hardware en error: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "El decoder falló", e)
        } finally {
            runCatching { codec.stop() }.onFailure { Log.w(TAG, "codec.stop(): ${it.message}") }
            runCatching { codec.release() }.onFailure { Log.w(TAG, "codec.release(): ${it.message}") }
            // Si nadie nos paró (error o Surface perdida), avisamos al servidor.
            if (generation.get() == myGeneration) running.set(false)
            Log.i(TAG, "Decoder detenido")
        }
    }

    /** Devuelve true si el access unit se consumió (si no, se reintentará en la siguiente vuelta). */
    private fun feedInput(codec: MediaCodec, accessUnit: ByteArray): Boolean {
        val index = codec.dequeueInputBuffer(INPUT_TIMEOUT_US)
        if (index < 0) return false

        val input = codec.getInputBuffer(index)
        if (input == null) {
            // Caso anómalo: devolvemos el buffer vacío para no dejar al decoder esperando.
            codec.queueInputBuffer(index, 0, 0, 0, 0)
            return false
        }
        input.clear()
        input.put(accessUnit)
        codec.queueInputBuffer(index, 0, accessUnit.size, System.nanoTime() / 1000, 0)
        recordFed(accessUnit.size)
        return true
    }

    private fun drainOutput(codec: MediaCodec, bufferInfo: MediaCodec.BufferInfo) {
        while (true) {
            val index = codec.dequeueOutputBuffer(bufferInfo, 0)
            when {
                index >= 0 -> {
                    codec.releaseOutputBuffer(index, true)
                    recordFrame()
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    Log.i(TAG, "Formato de salida: ${codec.outputFormat}")
                }
                else -> return // INFO_TRY_AGAIN u otros: nada que drenar
            }
        }
    }

    private fun resetWindow() {
        windowStartMs = 0L
        windowBytes = 0L
        windowFrames = 0
    }

    private fun recordFed(size: Int) {
        totalBytes += size
        windowBytes += size
        maybeRollStats()
    }

    private fun recordFrame() {
        totalFrames++
        windowFrames++
        maybeRollStats()
    }

    private fun maybeRollStats() {
        val now = SystemClock.elapsedRealtime()
        if (windowStartMs == 0L) {
            windowStartMs = now
            return
        }
        val elapsed = now - windowStartMs
        if (elapsed < 1000) return
        _stats.value = StreamStats(
            // bits por milisegundo == kbit/s
            bitrateKbps = (windowBytes * 8 / elapsed).toInt(),
            fps = (windowFrames * 1000 / elapsed).toInt(),
            frames = totalFrames,
            droppedFrames = totalDropped.get(),
            bytes = totalBytes,
        )
        resetWindow()
    }

    companion object {
        private const val TAG = "VideoPipeline"
        private const val MAX_PENDING_AUS = 24
        private const val POLL_TIMEOUT_MS = 10L
        private const val INPUT_TIMEOUT_US = 10_000L
    }
}
