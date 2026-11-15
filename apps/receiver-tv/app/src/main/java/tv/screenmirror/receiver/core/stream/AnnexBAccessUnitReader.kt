package tv.screenmirror.receiver.core.stream

/**
 * Agrupa un flujo H.264 Annex-B crudo en unidades de acceso (AU = una imagen completa).
 *
 * Fronteras (spec H.264 7.4.1.2.3, simplificada para vídeo progresivo):
 *  - Un VCL con `first_mb_in_slice == 0` tras haber visto otro VCL = nueva imagen.
 *    Los slices restantes de una imagen (multi-slice) se quedan en la AU actual:
 *    partir en cada VCL daría al decoder imágenes incompletas con timestamps distintos.
 *  - Un NAL de cabecera (SPS/PPS/SEI/AUD…) tras un VCL pertenece a la AU siguiente.
 *
 * El último NAL del buffer queda pendiente hasta que el siguiente start code lo acote.
 */
class AnnexBAccessUnitReader {

    private var data = ByteArray(0)
    private var auStart = 0
    private var processedNals = 0
    private var hasVcl = false

    fun feed(chunk: ByteArray, length: Int = chunk.size): List<ByteArray> {
        append(chunk, length)
        val accessUnits = mutableListOf<ByteArray>()
        while (processNextNal(accessUnits)) {
            // sigue mientras haya NALs completos por procesar
        }
        return accessUnits
    }

    private fun processNextNal(accessUnits: MutableList<ByteArray>): Boolean {
        val starts = findStartCodes()
        if (processedNals >= starts.size - 1) return false // sin siguiente start code no se puede acotar

        val start = starts[processedNals]
        val nalType = data[start + START_CODE_SIZE].toInt() and 0x1F

        if (nalType in VCL_TYPES) {
            val firstMb = firstMbInSlice(start)
            if (hasVcl && firstMb == 0) {
                // Nueva imagen: la AU anterior ya está completa.
                emitAccessUnit(accessUnits, start, triggerIsVcl = true)
            } else {
                hasVcl = true // primer slice de la imagen, o slice de continuación (multi-slice)
                processedNals++
            }
        } else if (hasVcl && nalType in HEADER_TYPES) {
            // Tras un VCL, esta cabecera precede a la imagen siguiente.
            emitAccessUnit(accessUnits, start, triggerIsVcl = false)
        } else {
            processedNals++
        }
        return true
    }

    private fun emitAccessUnit(accessUnits: MutableList<ByteArray>, start: Int, triggerIsVcl: Boolean) {
        if (start > auStart) accessUnits += data.copyOfRange(auStart, start)
        data = data.copyOfRange(start, data.size)
        auStart = 0
        processedNals = 1 // el NAL disparador pasa a ser el primero de la nueva AU
        hasVcl = triggerIsVcl
    }

    /**
     * Lee `first_mb_in_slice` —ue(v), el primer elemento de la cabecera de slice—
     * desde los bits posteriores al byte de cabecera NAL. Devuelve null si no se puede leer.
     */
    private fun firstMbInSlice(start: Int): Int? {
        var byteIndex = start + START_CODE_SIZE + 1 // +3 del start code +1 del cabecera NAL
        var bitIndex = 0

        fun nextBit(): Int? {
            if (byteIndex >= data.size) return null
            val bit = (data[byteIndex].toInt() shr (7 - bitIndex)) and 1
            bitIndex++
            if (bitIndex == 8) {
                bitIndex = 0
                byteIndex++
            }
            return bit
        }

        var zeros = 0
        while (nextBit() == 0) {
            if (++zeros > MAX_UE_ZEROS) return null
        }
        var value = (1 shl zeros) - 1
        repeat(zeros) {
            val bit = nextBit() ?: return null
            value = (value shl 1) or bit
        }
        return value
    }

    private fun append(chunk: ByteArray, length: Int) {
        if (data.size + length > MAX_BUFFER_BYTES) reset() // stream corrupto: sin estructura durante demasiado tiempo
        val merged = ByteArray(data.size + length)
        System.arraycopy(data, 0, merged, 0, data.size)
        System.arraycopy(chunk, 0, merged, data.size, length)
        data = merged
    }

    private fun reset() {
        data = ByteArray(0)
        auStart = 0
        processedNals = 0
        hasVcl = false
    }

    /** Posiciones de los start codes 00 00 01 (el cuarto byte de 00 00 00 01 queda como cero final del NAL anterior). */
    private fun findStartCodes(): List<Int> {
        val positions = ArrayList<Int>()
        var i = 0
        while (i <= data.size - START_CODE_SIZE) {
            if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()) {
                positions.add(i)
                i += START_CODE_SIZE
            } else {
                i++
            }
        }
        return positions
    }

    companion object {
        private const val START_CODE_SIZE = 3
        private const val MAX_BUFFER_BYTES = 8 * 1024 * 1024
        private const val MAX_UE_ZEROS = 20

        private val VCL_TYPES = 1..5

        /** NALs que, llegando tras un VCL, abren la siguiente AU: SEI, SPS, PPS, AUD, EOS, EOB, filler. */
        private val HEADER_TYPES = setOf(6, 7, 8, 9, 10, 11, 12)
    }
}
