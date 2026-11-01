package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceNovelTypeTest {
    private val base = "https://fixture.invalid"
    private val state = SourceState()
    private fun engine() = BookSourceEngine(mapOf("bookSourceUrl" to base, "bookSourceName" to "自编小说",
        "mainJs" to """
            function search(key,page){return [8,64,32,4,128].map(function(t){return {name:'条目'+t,bookUrl:'https://fixture.invalid/b/'+t,type:t,variable:{privateState:'fixture-only'}};});}
            function getBookInfo(book){return {type:64};}
            function getChapters(book){return [];}
            function getContent(chapter,book,nextChapterUrl){return '自编正文';}
        """), SourceRun(state = state, fetch = { _, _, _, _ -> error("Offline type contract") }))

    @Test fun nonNovelEntriesNeverEnterTheTextReaderAndVariablesStayNative() {
        val result = engine().execute("search", key = "条目") as Map<*, *>
        val rows = result["items"] as List<*>
        assertEquals(1, rows.size)
        val book = rows.single() as Map<*, *>
        assertEquals("条目8", book["name"])
        assertFalse(book.containsKey("variable"))
        assertEquals("fixture-only", state.get("book:$base/b/8", "privateState"))
    }

    @Test fun detailCannotSwitchANovelToAnUnsupportedConsumer() {
        val failure = runCatching { engine().execute("detail", "$base/b/8", book = mapOf("bookUrl" to "$base/b/8", "name" to "小说")) }.exceptionOrNull()
        assertEquals("书源返回非小说内容，本版仅支持文本小说", failure?.message)
    }
}
