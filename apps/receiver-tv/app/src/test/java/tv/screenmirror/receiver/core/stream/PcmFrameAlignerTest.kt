package tv.screenmirror.receiver.core.stream

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class PcmFrameAlignerTest {

    @Test
    fun `passes through whole frames untouched`() {
        val aligner = PcmFrameAligner(frameBytes = 4)
        val input = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        assertArrayEquals(input, aligner.feed(input, 0, input.size))
    }

    @Test
    fun `holds back a partial frame until the rest arrives`() {
        val aligner = PcmFrameAligner(frameBytes = 4)
        val first = aligner.feed(byteArrayOf(1, 2, 3, 4, 5, 6), 0, 6)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), first)

        val second = aligner.feed(byteArrayOf(7, 8, 9, 10), 0, 4)
        assertArrayEquals(byteArrayOf(5, 6, 7, 8), second)
    }

    @Test
    fun `keeps order when a read is smaller than one frame`() {
        val aligner = PcmFrameAligner(frameBytes = 4)
        assertEquals(0, aligner.feed(byteArrayOf(1), 0, 1).size)
        assertEquals(0, aligner.feed(byteArrayOf(2), 0, 1).size)
        assertEquals(0, aligner.feed(byteArrayOf(3), 0, 1).size)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), aligner.feed(byteArrayOf(4), 0, 1))
    }

    @Test
    fun `respects offset and size of the source buffer`() {
        val aligner = PcmFrameAligner(frameBytes = 2)
        val out = aligner.feed(byteArrayOf(9, 9, 1, 2, 3, 9), 2, 3)
        assertArrayEquals(byteArrayOf(1, 2), out)
        assertArrayEquals(byteArrayOf(3, 7), aligner.feed(byteArrayOf(7), 0, 1))
    }
}
