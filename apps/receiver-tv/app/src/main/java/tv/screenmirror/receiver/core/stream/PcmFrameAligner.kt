package tv.screenmirror.receiver.core.stream

/**
 * Reagrupa bytes PCM llegados de TCP en **frames completos** (muestra de todos los canales).
 *
 * TCP no respeta los límites que puso el emisor: un `read` puede acabar a mitad de una
 * muestra. Si ese resto se escribe tal cual al AudioTrack, todo lo que sigue queda
 * desalineado (canales cruzados, estática). Aquí el resto se retiene hasta el siguiente read.
 */
class PcmFrameAligner(private val frameBytes: Int) {

    init {
        require(frameBytes > 0) { "frameBytes debe ser positivo" }
    }

    private var pending = ByteArray(0)

    /** Devuelve los bytes alineados a frame disponibles tras añadir `size` bytes (puede ser vacío). */
    fun feed(buffer: ByteArray, offset: Int, size: Int): ByteArray {
        val combined = ByteArray(pending.size + size)
        System.arraycopy(pending, 0, combined, 0, pending.size)
        System.arraycopy(buffer, offset, combined, pending.size, size)

        val alignedLength = combined.size - combined.size % frameBytes
        pending = combined.copyOfRange(alignedLength, combined.size)
        return combined.copyOfRange(0, alignedLength)
    }
}
