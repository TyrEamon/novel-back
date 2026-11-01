package org.mewx.wenku8_flutter

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class SourceImageDiskBudgetTest {
    private fun fixture(run: (File) -> Unit) {
        val folder = Files.createTempDirectory("source-image-budget").toFile()
        try { run(folder) } finally { folder.deleteRecursively() }
    }

    @Test fun manyBelowBudgetWritesScanDirectoryOnlyOnce() = fixture { folder ->
        val budget = SourceImageDiskBudget(4096)
        repeat(1000) { index ->
            val file = File(folder, "$index.image").apply { writeBytes(byteArrayOf(1)) }
            budget.committed(folder, file, 0)
        }
        assertEquals(1000L, budget.knownBytes)
        assertEquals(1, budget.directoryScans)
        assertEquals(1000, folder.listFiles()!!.size)
    }

    @Test fun replacementAndExplicitRemovalRetainExactBudget() = fixture { folder ->
        val budget = SourceImageDiskBudget(100)
        val file = File(folder, "cover").apply { writeBytes(ByteArray(20)) }
        budget.committed(folder, file, 0)
        file.writeBytes(ByteArray(30)); budget.committed(folder, file, 20)
        assertEquals(30L, budget.knownBytes)
        file.delete(); budget.removed(30)
        assertEquals(0L, budget.knownBytes)
        assertEquals(1, budget.directoryScans)
    }

    @Test fun pressureEvictsOldestAndNeverTheNewImage() = fixture { folder ->
        val budget = SourceImageDiskBudget(10)
        val old = File(folder, "old").apply { writeBytes(ByteArray(5)); setLastModified(1000) }
        val recent = File(folder, "recent").apply { writeBytes(ByteArray(5)); setLastModified(2000) }
        budget.committed(folder, recent, 0)
        val current = File(folder, "new").apply { writeBytes(ByteArray(5)); setLastModified(0) }
        budget.committed(folder, current, 0)
        assertFalse(old.exists()); assertTrue(recent.exists()); assertTrue(current.exists())
        assertEquals(10L, budget.knownBytes)
    }

    @Test fun invalidationReconcilesExternalChangesAndIgnoresPartialWrites() = fixture { folder ->
        val budget = SourceImageDiskBudget(100)
        val file = File(folder, "cover").apply { writeBytes(ByteArray(10)) }
        budget.committed(folder, file, 0)
        File(folder, "external").writeBytes(ByteArray(20))
        File(folder, "unfinished.part").writeBytes(ByteArray(60))
        budget.invalidate(); budget.committed(folder, file, 10)
        assertEquals(30L, budget.knownBytes)
        assertEquals(2, budget.directoryScans)
    }
}
