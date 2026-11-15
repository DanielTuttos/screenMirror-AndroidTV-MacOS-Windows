package tv.screenmirror.receiver.core.stream

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AnnexBAccessUnitReaderTest {

    @Test
    fun `agrupa todos los slices de una imagen en la misma AU`() {
        val reader = AnnexBAccessUnitReader()
        val sps = nal3(0x67, 0x42, 0x00, 0x1E)
        val pps = nal3(0x68, 0xCE, 0x06, 0xE5)
        val idr = nal3(0x65, 0x88, 0x84, 0x21) // first_mb = 0 (empieza imagen)
        val slice1 = nal3(0x41, 0x40, 0x21) // first_mb > 0 (continúa la imagen)
        val slice2 = nal3(0x41, 0x40, 0x22) // first_mb > 0 (continúa la imagen)
        val nextFrame = nal3(0x41, 0x80, 0x01) // first_mb = 0 (nueva imagen)
        val trailing = nal3(0x41, 0x40, 0x02) // acota el siguiente start code

        assertTrue(reader.feed(sps + pps + idr + slice1 + slice2).isEmpty())

        val emitted = reader.feed(nextFrame + trailing)
        assertEquals(1, emitted.size)
        assertArrayEquals(sps + pps + idr + slice1 + slice2, emitted[0])
    }

    @Test
    fun `una cabecera tras un VCL abre la siguiente AU`() {
        val reader = AnnexBAccessUnitReader()
        val sps = nal3(0x67, 0x42, 0x00, 0x1E)
        val pps = nal3(0x68, 0xCE, 0x06, 0xE5)
        val idr = nal3(0x65, 0x88, 0x84, 0x21)
        val sei = nal3(0x06, 0x05, 0xFF)
        val nextSlice = nal3(0x41, 0x80, 0x01)

        assertTrue(reader.feed(sps + pps + idr + sei).isEmpty())

        val emitted = reader.feed(nextSlice)
        assertEquals(1, emitted.size)
        assertArrayEquals(sps + pps + idr, emitted[0])
    }

    @Test
    fun `emite cada imagen por separado`() {
        val reader = AnnexBAccessUnitReader()
        val frame1 = nal3(0x65, 0x80, 0x01)
        val frame2 = nal3(0x41, 0x80, 0x02)
        val frame3 = nal3(0x41, 0x80, 0x03)

        val emitted = reader.feed(frame1 + frame2 + frame3)
        assertEquals(1, emitted.size)
        assertArrayEquals(frame1, emitted[0])
    }

    @Test
    fun `tolera start codes de 4 bytes (deja el cero final en la AU anterior)`() {
        val reader = AnnexBAccessUnitReader()
        val frame1 = nal4(0x65, 0x80)
        val frame2 = nal4(0x41, 0x80)
        val frame3 = nal4(0x41, 0x80)

        val emitted = reader.feed(frame1 + frame2 + frame3)
        assertEquals(1, emitted.size)
        // El cero sobrante de 00 00 00 01 es un trailing_zero_8bits válido para el decoder.
        assertArrayEquals(frame1 + byteArrayOf(0), emitted[0])
    }

    @Test
    fun `tolera start codes partidos entre lecturas`() {
        val reader = AnnexBAccessUnitReader()
        val stream = nal3(0x65, 0x80) + nal3(0x41, 0x80) + nal3(0x41, 0x80)

        val emitted = mutableListOf<ByteArray>()
        for (byte in stream) {
            emitted += reader.feed(byteArrayOf(byte))
        }

        assertEquals(1, emitted.size)
        assertArrayEquals(nal3(0x65, 0x80), emitted[0])
    }

    @Test
    fun `sin start codes no emite nada`() {
        val reader = AnnexBAccessUnitReader()
        assertTrue(reader.feed(byteArrayOf(0x12, 0x34, 0x56)).isEmpty())
    }

    private fun nal3(vararg bytes: Int): ByteArray =
        byteArrayOf(0, 0, 1) + ByteArray(bytes.size) { bytes[it].toByte() }

    private fun nal4(vararg bytes: Int): ByteArray =
        byteArrayOf(0, 0, 0, 1) + ByteArray(bytes.size) { bytes[it].toByte() }
}
