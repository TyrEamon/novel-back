package org.mewx.wenku8_flutter

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.mewx.wenku8_flutter.legado.QueryTTF

/** Minimal self-authored sfnt, no third-party font/content fixtures. */
class SourceFontApiTest {
    private val base = "https://fixture.invalid"
    private fun BookSourceEngine.script(code: String) = evaluate("@js:$code", "fixture")
    private fun bytes(size: Int, write: ByteBuffer.() -> Unit) = ByteBuffer.allocate(size).order(ByteOrder.BIG_ENDIAN).apply(write).array()
    private fun ByteBuffer.short(value: Int) { putShort(value.toShort()) }
    private fun font(code: Int, format: Int = 4): ByteArray {
        val glyph = bytes(20) { short(1); short(0); short(0); short(100); short(100); short(2); short(0); put(0x31); put(0x33); put(0x35); put(100); put(100) }
        val cmap = when (format) {
            0 -> bytes(262) { short(0); short(262); short(0); position(6 + code); put(1) }
            6 -> bytes(12) { short(6); short(12); short(0); short(code); short(1); short(1) }
            else -> bytes(32) {
                short(4); short(32); short(0); short(4); short(4); short(1); short(0)
                short(code); short(0xffff); short(0); short(code); short(0xffff); short(1 - code); short(1); short(0); short(0)
            }
        }
        val tables = linkedMapOf(
            "name" to bytes(6) { short(0); short(0); short(6) },
            "head" to bytes(54) {
                putInt(0x10000); putInt(0); putInt(0); putInt(0x5f0f3cf5); short(0); short(1000); putLong(0); putLong(0)
                short(0); short(0); short(100); short(100); short(0); short(8); short(2); short(0); short(0)
            },
            "cmap" to bytes(12 + cmap.size) { short(0); short(1); short(3); short(1); putInt(12); put(cmap) },
            "loca" to bytes(6) { short(0); short(0); short(glyph.size / 2) },
            "maxp" to bytes(32) { putInt(0x10000); listOf(2, 3, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0).forEach { short(it) } },
            "glyf" to glyph,
        )
        val directory = 12 + tables.size * 16
        return bytes(directory + tables.values.sumOf { it.size }) {
            putInt(0x10000); short(tables.size); short(0); short(0); short(0)
            var offset = directory
            for ((name, data) in tables) { put(name.toByteArray()); putInt(0); putInt(offset); putInt(data.size); offset += data.size }
            tables.values.forEach { put(it) }
        }
    }

    @Test fun glyphQueriesKeepTheUpstreamSignatureAndSupportedCmapFormats() {
        for ((code, format) in listOf(65 to 0, 0x4e66 to 4, 0x4e66 to 6)) {
            val query = QueryTTF(font(code, format))
            assertEquals(1, query.getGlyfIdByUnicode(code))
            assertEquals("0,0|100,0|0,100", query.getGlyfByUnicode(code))
            assertEquals(code, query.getUnicodeByGlyf("0,0|100,0|0,100"))
            assertEquals(query.getGlyfByUnicode(code), query.getGlyfById(1))
            assertEquals(0, query.getGlyfIdByUnicode(66)); assertNull(query.getGlyfByUnicode(66))
        }
    }

    @Test fun scriptFontHelpersAcceptBase64AndBytesAndPreserveSupplementaryCharacters() {
        val error = Base64.getEncoder().encodeToString(font(0xe001))
        val correct = Base64.getEncoder().encodeToString(font(0x4e66))
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base), SourceRun(fetch = { _, _, _, _ -> error("No network") }))
        assertEquals("书😀 \tZ|书 \t|true|true|1", host.script("""
            var errorFont=java.queryBase64TTF('$error');var correctFont=java.queryTTF(java.base64DecodeToByteArray('$correct'));
            java.replaceFont('\uE001😀 \tZ',errorFont,correctFont)+'|'+java.replaceFont('\uE001😀 \tZ',errorFont,correctFont,true)+'|'+
            (java.queryTTF(null)===null)+'|'+(java.queryTTF({unknown:1})===null)+'|'+errorFont.getGlyfIdByUnicode(0xE001)
        """))
        assertEquals("unchanged", host.script("java.replaceFont('unchanged',null,null,true)"))
    }

    @Test fun fontCacheUsesSourceIdentityAndUrlAndCanBeDisabledOrCleared() {
        val calls = AtomicInteger()
        val state = SourceState()
        fun host(owner: SourceState = state) = BookSourceEngine(mapOf("bookSourceUrl" to base), SourceRun(state = owner,
            fetch = { _, _, _, _ -> error("Must fetch bytes") }, fetchBytes = { url, _, _, _, _ -> calls.incrementAndGet(); SourceReply(url, "", data = font(0x4e66)) }))
        val code = "java.queryTTF('$base/font.ttf').getGlyfIdByUnicode(0x4e66)"
        assertEquals("1", host().script(code)); assertEquals("1", host().script(code)); assertEquals(1, calls.get())
        host().script("java.queryTTF('$base/font.ttf',false)"); assertEquals(2, calls.get())
        host(SourceState()).script(code); assertEquals(3, calls.get())
        SourceFonts.clear(state); host().script(code); assertEquals(4, calls.get())
    }

    @Test fun malformedFontsAndCancellationFailBeforeUnboundedParsing() {
        assertTrue(runCatching { QueryTTF(ByteArray(4)) }.isFailure)
        val outside = font(0x4e66).apply { ByteBuffer.wrap(this).putInt(20, Int.MAX_VALUE) }
        assertTrue(runCatching { QueryTTF(outside) }.isFailure)
        val count = AtomicInteger()
        try { QueryTTF(font(0x4e66)) { if (count.incrementAndGet() > 10) throw CancellationException() }; fail("Font parse must cancel") }
        catch (_: CancellationException) { }
        // Reusing a parsed font doesn't call a completed/cancelled run's check.
        var completed = false
        val parsed = QueryTTF(font(0x4e66)) { check(!completed) }
        completed = true
        assertEquals("0,0|100,0|0,100", parsed.getGlyfById(1))
    }
}
