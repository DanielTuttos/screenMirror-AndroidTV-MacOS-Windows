package tv.screenmirror.receiver.core.stream

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import tv.screenmirror.receiver.domain.Outcome
import tv.screenmirror.receiver.domain.ReceiverError
import tv.screenmirror.receiver.domain.model.AudioRequest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Pipeline de reproducción de audio PCM con AudioTrack.
 *
 * Modo STREAM de baja latencia con un buffer pequeño para evitar acumular retraso
 * respecto al pipeline de vídeo.
 */
class AudioPipeline {

    private val running = AtomicBoolean(false)
    private var audioTrack: AudioTrack? = null
    private var aligner: PcmFrameAligner? = null
    private var prebufferTarget = 0
    private var bufferedBeforePlay = 0
    private var playing = false

    fun start(request: AudioRequest): Outcome<Unit> {
        if (!running.compareAndSet(false, true)) {
            return Outcome.Failure(ReceiverError.StreamBusy)
        }

        return try {
            val channelConfig = if (request.channels == 1) {
                AudioFormat.CHANNEL_OUT_MONO
            } else {
                AudioFormat.CHANNEL_OUT_STEREO
            }

            val minBufferSize = AudioTrack.getMinBufferSize(
                request.sampleRate,
                channelConfig,
                AudioFormat.ENCODING_PCM_16BIT,
            )

            if (minBufferSize <= 0) {
                running.set(false)
                return Outcome.Failure(ReceiverError.InvalidRequest("configuración de audio no soportada"))
            }

            // ~200 ms de colchón: la red por Wi-Fi tiene baches y un underrun suena a
            // chasquido/estática. Es latencia que ya queda por debajo de la del vídeo.
            val frameBytes = request.channels * BYTES_PER_SAMPLE
            val targetBytes = request.sampleRate * frameBytes * BUFFER_MILLIS / 1000
            val bufferSize = maxOf(minBufferSize * 2, targetBytes)

            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_UNKNOWN)
                .build()

            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(request.sampleRate)
                .setChannelMask(channelConfig)
                .build()

            val track = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            // No se llama a play() aquí: arranca en writePcm cuando el colchón está medio
            // lleno, para que la reproducción no empiece ya vacía y haga underrun.
            audioTrack = track
            aligner = PcmFrameAligner(frameBytes)
            prebufferTarget = bufferSize / 2
            bufferedBeforePlay = 0
            playing = false
            Log.i(TAG, "AudioTrack creado: ${request.sampleRate}Hz, ${request.channels}ch, buffer: ${bufferSize}B")
            Outcome.Success(Unit)
        } catch (e: Exception) {
            running.set(false)
            Log.e(TAG, "Error iniciando AudioTrack", e)
            Outcome.Failure(ReceiverError.InternalError)
        }
    }

    /**
     * Escribe muestras PCM al AudioTrack de forma síncrona/bloqueante desde el hilo de red.
     * Solo se escriben frames completos; el resto espera al siguiente read (ver `PcmFrameAligner`).
     */
    fun writePcm(buffer: ByteArray, offset: Int, size: Int): Int {
        val track = audioTrack ?: return -1
        val aligner = aligner ?: return -1
        if (!running.get()) return -1

        val aligned = aligner.feed(buffer, offset, size)
        if (aligned.isEmpty()) return 0
        val written = track.write(aligned, 0, aligned.size, AudioTrack.WRITE_BLOCKING)
        if (written > 0 && !playing) {
            bufferedBeforePlay += written
            if (bufferedBeforePlay >= prebufferTarget) {
                track.play()
                playing = true
            }
        }
        return written
    }

    fun isRunning(): Boolean = running.get()

    fun stop() {
        if (!running.getAndSet(false)) return
        try {
            audioTrack?.let {
                if (it.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    it.stop()
                }
                it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error liberando AudioTrack: ${e.message}")
        } finally {
            audioTrack = null
            aligner = null
            Log.i(TAG, "AudioTrack detenido")
        }
    }

    companion object {
        private const val TAG = "AudioPipeline"
        private const val BYTES_PER_SAMPLE = 2
        private const val BUFFER_MILLIS = 200
    }
}
