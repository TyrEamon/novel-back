package org.mewx.wenku8_flutter

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mewx.wenku8_flutter.legado.SourceResources

/** Only self-authored archives/resources in an isolated temporary directory. */
class SourceResourceApiTest {
    @get:Rule val temp = TemporaryFolder()
    private val base = "https://fixture.invalid"
    private fun BookSourceEngine.script(code: String) = evaluate("@js:$code", "fixture")
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun zip(vararg files: Pair<String, ByteArray>) = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> files.forEach { (name, data) -> zip.putNextEntry(ZipEntry(name)); zip.write(data); zip.closeEntry() } }
    }.toByteArray()
    private fun host(root: File = temp.newFolder(), content: ByteArray = "fixture".toByteArray(), state: SourceState = SourceState(),
                     observed: (String, String, Map<String, String>, ByteArray?, SourceHttpOptions) -> Unit = { _, _, _, _, _ -> }) =
        BookSourceEngine(mapOf("bookSourceUrl" to base, "header" to "{\"X-Fixture\":\"resource\"}"),
            SourceRun(state = state, filesRoot = root, fetch = { _, _, _, _ -> error("Binary resources must not be decoded as text") },
                fetchBytes = { url, method, headers, body, options -> observed(url, method, headers, body, options); SourceReply(url, "", data = content) }))

    @Test fun resourceDownloadsRoundTripBytesTextAndFileMethods() {
        val root = temp.newFolder()
        val host = host(root, "中文".toByteArray()) { url, _, headers, _, _ ->
            assertEquals("$base/test.txt", url); assertEquals("resource", headers["X-Fixture"])
        }
        assertEquals("中文|6|true|true|false|中文", host.script("""
            var path=java.downloadFile('$base/test.txt');var file=java.getFile(path);
            java.readTxtFile(path)+'|'+file.length()+'|'+file.exists()+'|'+file.isFile()+'|'+file.isDirectory()+'|'+java.bytesToStr(java.readFile(file.getPath()))
        """))
        assertEquals("true|true|true", host.script("var path=java.downloadFile('$base/test.txt');java.deleteFile(path)+'|'+(java.readFile(path)===null)+'|'+(java.readTxtFile(path)==='')"))
        assertEquals("true|true|true|0|empty", host.script("java.getFile('folder').mkdirs()+'|'+java.getFile('folder/empty').createNewFile()+'|'+java.getFile('folder').listFiles()[0].isFile()+'|'+java.getFile('folder/empty').length()+'|'+java.getFile('folder').list()[0]"))
        assertEquals("false|true|true", host.script("java.getFile('folder').delete()+'|'+java.deleteFile('folder')+'|'+(!java.getFile('folder').exists())"))
    }

    @Test fun deprecatedHexDownloadNeedsExplicitTypeAndDoesNotFetch() {
        val host = host(observed = { _, _, _, _, _ -> fail("Hex resource must not fetch") })
        assertEquals("", host.script("java.downloadFile('414243','$base/value.bin')"))
        assertEquals("ABC", host.script("var p=sourceApi.downloadFile('414243','$base/value,{\"type\":\"txt\"}');java.readTxtFile(p)"))
    }

    @Test fun zipReaderFindsTheSecondEntryAndMissingEntriesHaveUpstreamShapes() {
        val bytes = zip("first.txt" to "first".toByteArray(), "second.txt" to "第二项".toByteArray())
        val host = host(content = bytes)
        val encoded = hex(bytes)
        assertEquals("第二项|第二项|true|", host.script("java.getZipStringContent('$encoded','second.txt')+'|'+java.bytesToStr(java.getZipByteArrayContent('$base/archive.zip','second.txt'))+'|'+(java.getZipByteArrayContent('$encoded','missing')===null)+'|'+java.getZipStringContent('$encoded','missing')"))
    }

    @Test fun zipExtractionAndRelativeImportScriptRetainExplicitEvalAndRemoveTemporaryText() {
        val bytes = zip("lib.js" to "var fixtureImported='已载入';".toByteArray())
        val host = host(content = bytes)
        assertEquals("undefined|已载入|true", host.script("""
            var archive=java.downloadFile('$base/library.zip');var folder=java.unzipFile(archive);
            var text=java.importScript(folder+'/lib.js');var before=typeof fixtureImported;eval(text);
            var combined=java.getTxtInFolder(folder);before+'|'+fixtureImported+'|'+(!java.getFile(folder).exists() && combined===text)
        """))
        assertTrue(runCatching { host.script("java.importScript('missing.js')") }.isFailure)
        assertEquals("|", host.script("java.unArchiveFile('')+'|'+java.getTxtInFolder('')"))
    }

    @Test fun utf16AndExplicitLegacyCharsetRoundTrip() {
        val text = "自编中文"
        val host = host(content = text.toByteArray(charset("GB18030")))
        assertEquals(text, host.script("java.readTxtFile(java.downloadFile('$base/value.txt'),'GB18030')"))
        // Four GB18030 characters are also valid Big5 bytes: a statistical
        // detector cannot disambiguate them. Long samples are tested separately.
        val utf16 = host(content = byteArrayOf(0xff.toByte(), 0xfe.toByte()) + text.toByteArray(Charsets.UTF_16LE))
        assertEquals("\uFEFF$text", utf16.script("java.readTxtFile(java.downloadFile('$base/value.txt'))"))
    }

    @Test fun pathsTraversalSymlinksAndRootDeletionAreRejectedWithoutTouchingOutsideFiles() {
        val root = temp.newFolder()
        val outside = temp.newFile().apply { writeText("keep") }
        val host = host(root)
        assertTrue(runCatching { host.script("java.getFile('../outside')") }.isFailure)
        assertTrue(runCatching { host.script("java.deleteFile('/')") }.isFailure)
        Files.createSymbolicLink(File(root, "linked").toPath(), outside.toPath())
        assertTrue(runCatching { host.script("java.readTxtFile('linked')") }.isFailure)
        assertEquals("keep", outside.readText())
        for (name in listOf("../escaped.txt", "/escaped.txt", "folder/../../escaped.txt", "folder\\escaped.txt")) {
            val bad = host(root, zip(name to "bad".toByteArray()))
            assertTrue(name, runCatching { bad.script("java.unzipFile(java.downloadFile('$base/traversal.zip'))") }.isFailure)
        }
        assertFalse(File(root, "ArchiveTemp").exists())
        assertFalse(root.listFiles().orEmpty().any { it.name.startsWith("unpack-") })
    }

    @Test fun separateSourcesCannotReadEachOthersResources() {
        val one = host(content = "private-source-value".toByteArray())
        val two = host()
        val path = one.script("java.downloadFile('$base/shared.txt')").toString()
        assertEquals("private-source-value", one.script("java.readTxtFile('$path')"))
        assertEquals("", two.script("java.readTxtFile('$path')"))
    }

    @Test fun largeExpandedEntriesAndCancelledReadsLeaveNoExpandedResult() {
        val root = temp.newFolder()
        val bytes = zip("big.txt" to ByteArray(SourceResources.MAX_FILE + 1))
        val host = host(root, bytes)
        assertTrue(runCatching { host.script("java.unArchiveFile(java.downloadFile('$base/large.zip'))") }.isFailure)
        assertFalse(File(root, "ArchiveTemp").exists())
        assertTrue(runCatching { SourceResources.zipEntry(bytes, "big.txt") {} }.isFailure)
        File(root, "value.txt").writeBytes(ByteArray(32 * 1024))
        val checks = AtomicInteger()
        val resources = SourceResources(root, Any()) { if (checks.incrementAndGet() > 2) throw CancellationException() }
        try { resources.read("value.txt"); fail("Cancelled before accessing the resource") } catch (_: CancellationException) { }
    }

    @Test fun scriptsWithoutFileAuthorityKeepTheirExistingNetworkContract() {
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base), SourceRun(fetch = { url, _, _, _ -> SourceReply(url, "network-only") }))
        assertEquals("network-only", host.script("java.ajax('$base/body')"))
        assertTrue(runCatching { host.script("java.getFile('device-file')") }.isFailure)
        assertTrue(runCatching { host.execute("inspectScript", key = "java.getFile('device-file');({bookSourceName:'bad'})") }.isFailure)
    }
}
