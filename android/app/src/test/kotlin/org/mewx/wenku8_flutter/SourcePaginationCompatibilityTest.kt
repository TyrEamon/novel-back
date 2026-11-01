package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourcePaginationCompatibilityTest {
    private val base = "https://fixture.invalid"
    private fun engine(source: Map<String, Any?>, pages: Map<String, String>, state: SourceState = SourceState(), calls: MutableList<String> = mutableListOf()) =
        BookSourceEngine(mapOf("bookSourceUrl" to base, "bookSourceName" to "自编测试") + source,
            SourceRun(state = state, fetch = { url, _, _, _ -> calls.add(url); SourceReply(url, pages[url] ?: error("Unexpected fixture request")) }))

    @Test fun fullChapterReplacementRunsOnceAfterJoiningPages() {
        val source = mapOf("ruleContent" to mapOf("content" to "p@text", "nextContentUrl" to "a@href",
            "replaceRegex" to "@js:java.put('replacements',String(Number(java.get('replacements')||0)+1));result.replace(/尾\\s*头/g,'连接')"))
        val state = SourceState()
        val host = engine(source, mapOf("$base/one" to "<p>前尾</p><a href='/two'>下一页</a>", "$base/two" to "<p>头后</p>"), state)
        assertEquals("前连接后", host.execute("content", "$base/one", chapter = mapOf("url" to "$base/one")))
        assertEquals("1", state.get("chapter:$base/one", "replacements"))
    }

    @Test fun explicitSiblingPagesDoNotRecursivelyExpandTheirNavigation() {
        val source = mapOf("ruleContent" to mapOf("content" to "p@text", "nextContentUrl" to "a@href"))
        val calls = mutableListOf<String>()
        val host = engine(source, mapOf(
            "$base/one" to "<p>甲</p><a href='/two'>2</a><a href='/three'>3</a>",
            "$base/two" to "<p>乙</p><a href='/never'>其他导航</a>", "$base/three" to "<p>丙</p>"), calls = calls)
        assertEquals("甲\n\n乙\n\n丙", host.execute("content", "$base/one"))
        assertEquals(listOf("$base/one", "$base/two", "$base/three"), calls)
    }

    @Test fun contentKeepsRawEntityEscapingUntilAfterHtmlFormatting() {
        val source = mapOf("ruleContent" to mapOf("content" to "p@html"))
        val text = engine(source, mapOf("$base/one" to "<p>示例：&lt;div&gt;文字&lt;/div&gt; &amp; 完成</p>"))
            .execute("content", "$base/one") as String
        assertEquals("示例：<div>文字</div> & 完成", text)
    }

    @Test fun imageOptionJsonSurvivesFormattingReplacementAndTheReaderBoundary() {
        val locator = "$base/image.png,{\"headers\":{\"Referer\":\"$base/book\"}}"
        val source = mapOf("ruleContent" to mapOf("content" to "@js:JSON.parse(src).html", "replaceRegex" to "##第一段##开头"))
        val body = org.mewx.wenku8_flutter.legado.js.SourceGson.gson.toJson(mapOf("html" to "<p>第一段</p><img src=\"$locator\"><p>结尾</p>"))
        val text = engine(source, mapOf("$base/one" to body)).execute("content", "$base/one") as String
        assertEquals("开头\n\n<!--image-->$locator<!--image-->\n\n结尾", text)
    }

    @Test fun tocFormattingUsesOneBasedIndexAndAPersistentFormattingScope() {
        val source = mapOf("ruleToc" to mapOf("chapterList" to "li", "chapterName" to "a@text", "chapterUrl" to "a@href",
            "formatJs" to "++gInt;index+' / '+gInt+' '+title"))
        val rows = engine(source, mapOf("$base/toc" to "<ul><li><a href='/one'>甲</a></li><li><a href='/two'>乙</a></li></ul>"))
            .execute("toc", "$base/toc") as List<*>
        assertEquals(listOf("1 / 1 甲", "2 / 2 乙"), rows.map { (it as Map<*, *>)["name"] })
        assertEquals(listOf(0, 1), rows.map { (it as Map<*, *>)["index"] })
    }

    @Test fun duplicateChapterKeepsTheLastRowWithoutDroppingASeparateVolume() {
        val source = mapOf("ruleToc" to mapOf("chapterList" to "li", "chapterName" to "a@text", "chapterUrl" to "a@href", "isVolume" to "@data-volume"))
        val rows = engine(source, mapOf("$base/toc" to """
            <ul><li data-volume='true'><a href='/one'>卷一</a></li><li><a href='/one'>旧标题</a></li>
            <li><a href='/two'>第二章</a></li><li><a href='/one'>正确标题</a></li></ul>
        """)).execute("toc", "$base/toc") as List<*>
        assertEquals(listOf("卷一", "第二章", "正确标题"), rows.map { (it as Map<*, *>)["name"] })
    }

    @Test fun variablesWrittenBeforeTheRowUrlAreMovedWithTheirBookOrChapter() {
        val state = SourceState()
        val source = mapOf("ruleSearch" to mapOf("bookList" to "li", "name" to "a@text@js:book.putVariable('selected',result);result", "bookUrl" to "a@href"),
            "searchUrl" to "$base/search")
        engine(source, mapOf("$base/search" to "<ul><li><a href='/a'>甲</a></li><li><a href='/b'>乙</a></li></ul>"), state)
            .execute("search", key = "自编")
        assertEquals("甲", state.get("book:$base/a", "selected"))
        assertEquals("乙", state.get("book:$base/b", "selected"))
        val tocSource = mapOf("ruleToc" to mapOf("chapterList" to "a", "chapterName" to "text@js:chapter.putVariable('selected',result);result", "chapterUrl" to "href"))
        engine(tocSource, mapOf("$base/toc" to "<a href='/one'>第一章</a>"), state).execute("toc", "$base/toc")
        assertEquals("第一章", state.get("chapter:$base/one", "selected"))
        assertEquals("", state.get("book:", "selected"))
        assertEquals("", state.get("chapter:", "selected"))
    }
}
