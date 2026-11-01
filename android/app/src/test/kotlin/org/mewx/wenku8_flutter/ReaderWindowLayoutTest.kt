package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class ReaderWindowLayoutTest {
    @Test fun cutoutPolicyDoesNotDependOnHiddenStatusBarsOrOrientation() {
        assertNull(ReaderWindowLayout.cutoutMode(24))
        assertNull(ReaderWindowLayout.cutoutMode(27))
        assertEquals(1, ReaderWindowLayout.cutoutMode(28))
        assertEquals(1, ReaderWindowLayout.cutoutMode(29))
        assertEquals(3, ReaderWindowLayout.cutoutMode(30))
        assertEquals(3, ReaderWindowLayout.cutoutMode(36))
    }

    @Test fun backgroundsDecodeWithinTheBoundBeforeAllocation() {
        assertEquals(1, ReaderBackgroundImage.sampleSize(390, 844))
        assertEquals(2, ReaderBackgroundImage.sampleSize(4000, 3000))
        assertEquals(2, ReaderBackgroundImage.sampleSize(3000, 4000))
        assertEquals(32, ReaderBackgroundImage.sampleSize(65535, 32768))
        for ((width, height) in listOf(0 to 12, -1 to 1, 12 to 0, 65536 to 100)) {
            assertThrows(IllegalArgumentException::class.java) { ReaderBackgroundImage.sampleSize(width, height) }
        }
    }
}
