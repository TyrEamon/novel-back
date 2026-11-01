package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceDocumentMetadataTest {
    private val base = "https://fixture.invalid"
    private val detail = """
        <main><div class="card"><div class="card-body">
        <h1>纸间之旅</h1><dl><dd><a href="/books?q%5Bauthors_id_eq%5D=7">小舟</a></dd>
        <dd><a href="/books?q%5Bgenres_id_eq%5D=3">奇幻</a><a href="/books?q%5Bgenres_id_eq%5D=8">冒险</a></dd></dl>
        <h2>簡介</h2><p>故事里的人谈起评论，但这句话本来就属于小说简介。</p><p>小舟的旅程从一座海边的小小书店开始，直到抵达远方。</p>
        <h2>分卷</h2><div class="accordion-item"><h3 class="accordion-header"><a href="/c1">第一卷</a></h3>
        <div class="accordion-collapse"><a href="/c1">第一话 出发</a><a href="/c2">第二话 书店</a></div></div>
        <div class="row"><h2>評論</h2></div><div class="row"><p>这是读者写下的一条很长的评论，不是故事的简介。</p><a href="/user">小舟</a></div>
        </div></div></main>
    """.trimIndent()

    private fun engine(source: Map<String, Any?>, pages: Map<String, String>): BookSourceEngine =
        BookSourceEngine(mapOf("bookSourceUrl" to base) + source, SourceRun(fetch = { url, _, _, _ ->
            SourceReply(url, pages[url] ?: error("Unknown fixture page: $url"))
        }))

    @Test fun indexedTitleSelectionCannotRenameDifferentBooksToTheSameRecommendation() {
        fun page(name: String) = """<html><head><title>$name - 自编书库</title></head><body>
            <b>本周推荐</b><a href="/books/recommended"><b>星海旅途</b></a>
            <main><h1><b>$name</b></h1><p>这才是当前作品的内容。</p></main></body></html>"""
        val rules = mapOf("ruleBookInfo" to mapOf("name" to "tag.b.1@text"))
        val runner = engine(rules, mapOf("$base/books/a" to page("纸间之旅"), "$base/books/b" to page("海边来信")))
        for ((id, name) in listOf("a" to "纸间之旅", "b" to "海边来信")) {
            val result = runner.execute("detail", "$base/books/$id", book = mapOf("name" to name, "bookUrl" to "$base/books/$id")) as Map<*, *>
            assertEquals(name, result["name"])
            assertEquals("$base/books/$id", result["bookUrl"])
        }
    }

    @Test fun titleRepairRequiresDocumentEvidenceAndPreservesAlternateAndScriptTitles() {
        val html = """<title>正式完整书名 - 自编书库</title><h1>正式完整书名</h1><a href="/other">推荐之书</a>"""
        val metadata = SourceDocumentMetadata.parse(html, "$base/book")!!
        assertEquals("正式完整书名", metadata.bookName("正式完整书名", "简称"))
        assertEquals("自定义显示名", metadata.bookName("自定义显示名", "正式完整书名"))
        assertEquals("推荐之书", metadata.bookName("推荐之书", "正文中不存在的名称"))
        val explicit = SourceDocumentMetadata.parse("""<meta property="og:novel:book_name" content="正式完整书名"><b>推荐之书</b>""", "$base/book")!!
        assertEquals("正式完整书名", explicit.bookName("推荐之书", "正式完整书名"))
        assertEquals("自定义显示名", explicit.bookName("自定义显示名", "正式完整书名"))
        val oldPolluted = SourceDocumentMetadata.parse("""<meta property="og:novel:book_name" content="正式完整书名"><a href="/other"><b>推荐之书</b></a>""", "$base/book")!!
        assertEquals("正式完整书名", oldPolluted.bookName("推荐之书", "推荐之书"))
        val json = engine(mapOf("ruleBookInfo" to mapOf("name" to "$.name", "canReName" to "true")), mapOf("$base/book" to """{"name":"接口正式名称"}"""))
            .execute("detail", "$base/book", book = mapOf("name" to "列表简称")) as Map<*, *>
        assertEquals("接口正式名称", json["name"])
    }

    @Test fun titleValidationRecognizesCrossOriginPromotionsAndNotCurrentPageAnchors() {
        fun metadata(href: String) = SourceDocumentMetadata.parse("""<title>海边来信 - 自编书库</title>
            <a href="$href"><b>推荐之书</b></a><main><b>海边来信</b></main>""", "$base/book")!!
        assertEquals("海边来信", metadata("http://fixture.invalid/promoted").bookName("推荐之书", "海边来信"))
        assertEquals("海边来信", metadata("https://elsewhere.invalid/promoted").bookName("推荐之书", "海边来信"))
        assertEquals("推荐之书", metadata("http://fixture.invalid/book#toc").bookName("推荐之书", "海边来信"))
    }

    @Test fun truncatedListingAndPreviouslyPollutedNamesRecoverTheVerifiedFullTitle() {
        val title = "海边来信与一间旧书店所连结的漫长夏日记忆"
        val html = """<title>$title - 自编作者 - 自编书库</title>
            <a href="http://external.invalid/promotion"><b>推荐之书</b></a><main><span><b>$title</b></span></main>"""
        val metadata = SourceDocumentMetadata.parse(html, "$base/book")!!
        assertEquals(title, metadata.bookName("推荐之书", "海边来信与一间旧书店所连结的漫长夏日"))
        assertEquals(title, metadata.bookName("推荐之书", "推荐之书"))
        assertEquals("推荐之书", metadata.bookName("推荐之书", "完全不同的另一本作品"))
        val alias = SourceDocumentMetadata.parse("""<title>纸间的远方来信 - 自编书库</title><a href="/other"><b>推荐之书</b></a><b>纸间的远方来信</b>""", "$base/book")!!
        assertEquals("纸间的远方来信", alias.bookName("推荐之书", "纸间的远方来信（别名）"))
    }

    @Test fun explicitTagRowsSupplementSourceKindsWithoutIncludingSecondaryContent() {
        val html = """<title>自编故事</title><h1>自编故事</h1><p class="author">作者：自编作者</p>
            <p class="kind">自编文库 已完结</p><p><b>作品Tags：奇幻 冒险 女性视角</b></p>
            <aside><b>作品Tags：不应加入</b></aside><div class="comments"><b>Tags: 评论标签</b></div>"""
        val result = engine(mapOf("ruleBookInfo" to mapOf("name" to "h1@text", "author" to ".author@text", "kind" to ".kind@text")),
            mapOf("$base/book" to html)).execute("detail", "$base/book") as Map<*, *>
        assertEquals("自编文库,已完结,奇幻,冒险,女性视角", result["kind"])
        assertEquals("自编作者", result["author"])
        assertEquals(true, result["complete"])
        val structured = SourceDocumentMetadata.parse("""<dl><dt>作品标签</dt><dd><a href="/tags/fantasy">奇幻</a> 冒险</dd><dt>作者</dt><dd>不应加入</dd></dl>
            <p><strong>Tags:</strong><a href="/tags/fantasy">奇幻</a> 旅行</p><meta itemprop="genre" content="女性视角">""", "$base/book")!!
        assertEquals(listOf("奇幻", "女性视角", "冒险", "旅行"), structured.genres("奇幻"))
    }

    @Test fun authorLabelsAreRemovedOnlyWithAnExplicitSeparator() {
        for ((raw, expected) in listOf("作者：小舟" to "小舟", "著者: 小舟" to "小舟", "Author: Mira Vale" to "Mira Vale",
            "Author Mira Vale" to "Mira Vale", "作者菌" to "作者菌", "The Author" to "The Author")) {
            assertEquals(expected, SourceDocumentMetadata.authorName(raw))
        }
    }

    @Test fun broadIntroSelectionUsesActualSectionBoundariesNotWordsOrLength() {
        val rules = mapOf("ruleBookInfo" to mapOf("name" to "h1@text", "author" to "dl dd.0@text",
            "kind" to "dd.1@a@text", "intro" to ".card-body@p@text"))
        val result = engine(rules, mapOf("$base/book" to detail)).execute("detail", "$base/book") as Map<*, *>
        assertEquals("故事里的人谈起评论，但这句话本来就属于小说简介。\n\n小舟的旅程从一座海边的小小书店开始，直到抵达远方。", result["intro"])
        assertEquals("$base/books?q%5Bauthors_id_eq%5D=7", result["authorUrl"])
        assertEquals(mapOf("奇幻" to "$base/books?q%5Bgenres_id_eq%5D=3", "冒险" to "$base/books?q%5Bgenres_id_eq%5D=8"), result["tagUrls"])
        assertEquals("奇幻,冒险", result["kind"])
    }

    @Test fun validCustomIntroAndJsonResultsAreNotRewritten() {
        val custom = engine(mapOf("ruleBookInfo" to mapOf("intro" to "@js:'我的自定义简介：评论也是故事的一部分。'")),
            mapOf("$base/book" to detail)).execute("detail", "$base/book") as Map<*, *>
        assertEquals("我的自定义简介：评论也是故事的一部分。", custom["intro"])
        val json = engine(mapOf("ruleBookInfo" to mapOf("intro" to "$.intro")),
            mapOf("$base/book" to """{"intro":"剧情包含评论这两个字，也不应该被截断。"}"""))
            .execute("detail", "$base/book") as Map<*, *>
        assertEquals("剧情包含评论这两个字，也不应该被截断。", json["intro"])
        assertFalse(json.containsKey("authorUrl"))
    }

    @Test fun reviewAndExternalLinksCannotBecomeAuthorCollections() {
        val html = """<h1>书</h1><h2>简介</h2><p>正常简介。</p><h2>评论</h2><div><p>这是评论。</p><a href="/users/1">小舟</a></div>"""
        assertNull(SourceDocumentMetadata.parse(html, "$base/book")!!.authorUrl("小舟"))
        val external = """<dl><a href="https://external.invalid/authors/1">小舟</a></dl>"""
        assertNull(SourceDocumentMetadata.parse(external, "$base/book")!!.authorUrl("小舟"))
    }

    @Test fun actualNextLinkIsFollowedAndLastPagerEndsAPlaceholderListing() {
        val source = mapOf("searchUrl" to "/books?page={{page}}", "ruleSearch" to mapOf(
            "bookList" to ".books a", "name" to "text", "bookUrl" to "href"))
        val runner = engine(source, mapOf(
            "$base/books?page=1" to """<link rel="next" href="/books?cursor=2"><div class="books"><a href="/b1">第一本</a></div>""",
            "$base/books?cursor=2" to """<div class="books"><a href="/b2">第二本</a></div><nav class="pagination"><a rel="prev" href="/books?page=1">上一页</a><span class="disabled">下一页</span></nav>"""
        ))
        val first = runner.execute("search") as Map<*, *>
        assertEquals("$base/books?cursor=2", first["nextUrl"])
        assertEquals(true, first["hasMore"])
        val second = runner.execute("search", url = first["nextUrl"].toString(), page = 2) as Map<*, *>
        assertEquals(false, second["hasMore"])
        assertEquals("第二本", ((second["items"] as List<*>).single() as Map<*, *>)["name"])
    }

    @Test fun automaticNextNeverUsesChapterLinksExternalHostsOrDisabledButtons() {
        val html = """<a class="next" href="/chapter2">下一章</a><nav class="pagination">
            <a href="https://external.invalid/page/2">下一页</a><li class="disabled"><a href="/page/2">下一页</a></li></nav>"""
        val navigation = SourceDocumentMetadata.parse(html, "$base/page/1")!!.navigation()
        assertNull(navigation.nextUrl)
        assertTrue(navigation.hasPager)
    }

    @Test fun ordinaryNavigationDoesNotPretendToBeAPagerAndStandaloneNextLinksWork() {
        val html = """<nav role="navigation"><a href="/">首页</a></nav>"""
        assertFalse(SourceDocumentMetadata.parse(html, "$base/books?page=1")!!.navigation().hasPager)
        val next = SourceDocumentMetadata.parse(html + """<a class="next" href="?cursor=2">下一頁 »</a>""", "$base/books?page=1")!!.navigation()
        assertEquals("$base/books?cursor=2", next.nextUrl)
    }

    @Test fun structuralVolumeHeadersDoNotConsumeTheRealFirstChapterWithTheSameUrl() {
        val source = mapOf("ruleToc" to mapOf("chapterList" to ".accordion-item@a", "chapterName" to "text", "chapterUrl" to "href"))
        val rows = engine(source, mapOf("$base/book" to detail)).execute("toc", "$base/book") as List<*>
        val volume = rows[0] as Map<*, *>
        val first = rows[1] as Map<*, *>
        assertEquals(true, volume["isVolume"])
        assertEquals("第一卷", volume["name"])
        assertEquals(false, first["isVolume"])
        assertEquals("第一话 出发", first["name"])
        assertEquals(volume["url"], first["url"])
        assertEquals("第一卷", first["volumeTitle"])
    }

    @Test fun reverseOrderAndHeaderExcludingRulesKeepPerChapterVolumeOwnership() {
        val html = detail + """<div class="accordion-item"><h3 class="accordion-header"><a href="/c3">第二卷</a></h3>
            <div class="accordion-collapse"><a href="/c3">第三话 重逢</a></div></div>"""
        val source = mapOf("ruleToc" to mapOf("chapterList" to "-.accordion-collapse@a", "chapterName" to "text", "chapterUrl" to "href"))
        val rows = engine(source, mapOf("$base/book" to html)).execute("toc", "$base/book") as List<*>
        assertEquals(3, rows.size)
        assertEquals(rows.toString(), "第二卷", (rows.first() as Map<*, *>)["volumeTitle"])
        assertEquals("第一卷", (rows.last() as Map<*, *>)["volumeTitle"])
        assertTrue(rows.all { (it as Map<*, *>)["isVolume"] == false })
    }

    @Test fun explicitVolumeRuleRetainsItsOriginalContract() {
        val source = mapOf("ruleToc" to mapOf("chapterList" to ".accordion-item@a", "chapterName" to "text", "chapterUrl" to "href", "isVolume" to "@js:false"))
        val rows = engine(source, mapOf("$base/book" to detail)).execute("toc", "$base/book") as List<*>
        assertTrue(rows.all { (it as Map<*, *>)["isVolume"] == false })
        assertTrue(rows.all { (it as Map<*, *>)["volumeTitle"] == "" })
    }

    @Test fun explorationHeadingsAndLayoutMetadataAreRetained() {
        val result = engine(mapOf("exploreUrl" to """[{"title":"分类","url":"","style":{"layout_flexBasisPercent":1}},{"title":"奇幻","url":"/fantasy","style":{"layout_flexBasisPercent":0.5}}]"""), emptyMap())
            .execute("explores") as List<*>
        assertEquals("", (result[0] as Map<*, *>)["url"])
        assertEquals(0.5, ((result[1] as Map<*, *>)["style"] as Map<*, *>)["layout_flexBasisPercent"])
    }
}
