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

            // Buffer ajustado a 2x el mínimo (suficiente para evitar underruns sin añadir latencia de cola)
            val bufferSize = minBufferSize * 2

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

            track.play()
            audioTrack = track
            Log.i(TAG, "AudioTrack iniciado: ${request.sampleRate}Hz, ${request.channels}ch, buffer: ${bufferSize}B")
            Outcome.Success(Unit)
        } catch (e: Exception) {
            running.set(false)
            Log.e(TAG, "Error iniciando AudioTrack", e)
            Outcome.Failure(ReceiverError.InternalError)
        }
    }

    /**
     * Escribe muestras PCM al AudioTrack de forma síncrona/bloqueante desde el hilo de red.
     */
    fun writePcm(buffer: ByteArray, offset: Int, size: Int): Int {
        val track = audioTrack ?: return -1
        if (!running.get()) return -1
        return track.write(buffer, offset, size, AudioTrack.WRITE_BLOCKING)
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
            Log.i(TAG, "AudioTrack detenido")
        }
    }

    companion object {
        private const val TAG = "AudioPipeline"
    }
}
