package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class BookInfoCompatibilityTest {
    private val base = "https://fixture.invalid"
    private fun engine(rule: Map<String, Any?>, body: String, state: SourceState = SourceState(), cancelled: () -> Boolean = { false }) =
        BookSourceEngine(mapOf("bookSourceUrl" to base, "ruleBookInfo" to rule), SourceRun(state = state, cancelled = cancelled,
            fetch = { _, _, _, _ -> SourceReply("$base/redirect", body) }))

    @Test fun selectedBookIdentityIsPreservedButRulesStillExecute() {
        val state = SourceState()
        val result = engine(mapOf("name" to "@js:java.put('parsed','yes'); '推荐作品'", "author" to "h2@text"),
            "<h1>推荐作品</h1><h2>另一位作者</h2>", state)
            .execute("detail", "$base/book", book = mapOf("bookUrl" to "$base/book", "name" to "当前作品", "author" to "当前作者")) as Map<*, *>
        assertEquals("当前作品", result["name"])
        assertEquals("当前作者", result["author"])
        assertEquals("yes", state.get("book:$base/book", "parsed"))
        assertEquals("$base/book", result["tocUrl"])
    }

    @Test fun explicitRenameAndInitFollowUpstreamContract() {
        val result = engine(mapOf("init" to ".book", "name" to "h1@text", "author" to "h2@text", "canReName" to "true", "tocUrl" to "a@href"),
            "<aside><h1>广告</h1></aside><main class='book'><h1>正式作品 作者：某人</h1><h2>作者：小舟 著</h2><a href='/toc'>目录</a></main>")
            .execute("detail", "$base/book", book = mapOf("name" to "简称", "author" to "旧作者")) as Map<*, *>
        assertEquals("正式作品", result["name"])
        assertEquals("小舟", result["author"])
        assertEquals("$base/toc", result["tocUrl"])
    }

    @Test fun optionalFieldsPreserveSavedValuesAndReportSafeWarnings() {
        val rule = mapOf("name" to "h1@text", "intro" to "@js:throw Error('secret-body')", "coverUrl" to "@js:throw Error('secret-header')", "lastChapter" to "h2@text", "kind" to "i@text")
        val result = engine(rule, "<h1>作品</h1><h2>新章节</h2><i>奇幻</i>").execute("detail", "$base/book", book = mapOf(
            "intro" to "已保存简介", "coverUrl" to "$base/cover.png", "kind" to "旧分类")) as Map<*, *>
        assertEquals("已保存简介", result["intro"])
        assertEquals("$base/cover.png", result["coverUrl"])
        assertEquals("新章节", result["lastChapter"])
        assertEquals("奇幻", result["kind"])
        assertEquals(listOf("书源简介：JavaScript 规则执行失败", "书源封面：JavaScript 规则执行失败"), result["ruleWarnings"])
        assertFalse(result.toString().contains("secret"))
    }

    @Test fun requiredFieldsAndCancellationStillFail() {
        val failure = runCatching { engine(mapOf("tocUrl" to "@js:throw Error('private')"), "<h1>书</h1>")
            .execute("detail", "$base/book") }.exceptionOrNull()
        assertEquals("书源目录地址：JavaScript 规则执行失败", sourceRuleFailureMessage(failure as Exception))
        var checks = 0
        val cancelled = runCatching { engine(mapOf("intro" to "@js:'简介'"), "<h1>书</h1>", cancelled = { ++checks > 4 })
            .execute("detail", "$base/book") }.exceptionOrNull()
        assertTrue(cancelled is CancellationException)
    }

    @Test fun introAndWordCountFormattingMatchUpstream() {
        val result = engine(mapOf("name" to "h1@text", "intro" to "#intro@html", "wordCount" to "@js:'120000'"),
            "<h1>书</h1><div id='intro'><p>第一段。</p><p>第二段。&nbsp;</p></div>")
            .execute("detail", "$base/book") as Map<*, *>
        // getString unescapes &nbsp; before HtmlFormatter; the pinned upstream
        // formatter's Java-regex whitespace does not strip a Unicode NBSP.
        assertEquals("第一段。\n第二段。\u00a0", result["intro"])
        assertEquals("12万字", result["wordCount"])
    }

    @Test fun laterFieldsCanReadTheParsedBookIdentity() {
        val result = engine(mapOf("name" to "h1@text", "author" to "h2@text", "intro" to "@js:book.name+' / '+book.author"),
            "<h1>作品</h1><h2>小舟</h2>").execute("detail", "$base/book") as Map<*, *>
        assertEquals("作品 / 小舟", result["intro"])
    }
    @Test fun initAndFieldScriptsCanMutateTheSameBookObject() {
        val result = engine(mapOf("init" to "@js:book.setName('初始化书名');java.getElement('main')", "name" to "",
            "author" to "@js:book.setWordCount('12万字');'小舟'", "intro" to "@js:book.getName()+' / '+book.getWordCount()"),
            "<main><p>自编详情</p></main>").execute("detail", "$base/book") as Map<*, *>
        assertEquals("初始化书名", result["name"])
        assertEquals("小舟", result["author"])
        assertEquals("12万字", result["wordCount"])
        assertEquals("初始化书名 / 12万字", result["intro"])
    }
}
