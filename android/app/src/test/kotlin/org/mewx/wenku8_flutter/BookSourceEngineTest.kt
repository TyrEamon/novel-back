package org.mewx.wenku8_flutter

import org.junit.Test
import org.junit.Assert.*
import java.util.concurrent.CancellationException

class BookSourceEngineTest {
    private val base = "https://fixture.invalid"
    private fun engine(source: Map<String, Any?> = emptyMap(), pages: Map<String, String> = emptyMap(),
        request: ((String, String, Map<String, String>, ByteArray?) -> SourceReply)? = null): BookSourceEngine =
        BookSourceEngine(mapOf("bookSourceUrl" to base) + source, SourceRun(fetch = request ?: { url, _, _, _ ->
            SourceReply(url, pages[url] ?: error("Unknown fixture page: $url"))
        }))
    @Test fun htmlSearchResolvesRelativeUrlsAndPagination() {
        val source = mapOf("searchUrl" to "/search?q={{key}}&p={{page}}", "ruleSearch" to mapOf(
            "bookList" to "class.books@tag.li", "name" to "tag.a@text", "author" to "class.author@text##作者：##",
            "bookUrl" to "tag.a@href", "coverUrl" to "tag.img@src"))
        val runner = engine(source, request = { url, method, _, _ ->
            assertEquals("$base/search?q=%E6%98%9F%E6%B5%B7&p=2", url); assertEquals("GET", method)
            SourceReply(url, "<ul class='books'><li><a href='/book/1'>星海</a><b class='author'>作者：小舟</b><img src='/cover.jpg'></li></ul>")
        })
        val result = runner.execute("search", key = "星海", page = 2) as Map<*, *>
        val book = (result["items"] as List<*>).single() as Map<*, *>
        assertEquals("星海", book["name"]); assertEquals("小舟", book["author"])
        assertEquals("$base/book/1", book["bookUrl"]); assertEquals("$base/cover.jpg", book["coverUrl"])
        assertEquals(true, result["hasMore"])
    }
    @Test fun jsonSearchAndSafeJavascriptTransform() {
        val source = mapOf("searchUrl" to "$base/api?p={{page+1}}", "ruleSearch" to mapOf(
            "bookList" to "$.items[*]", "name" to "$.name@js:result.trim()", "author" to "$.author",
            "bookUrl" to "$.url", "kind" to "$.tags[*]"))
        val result = engine(source, mapOf("$base/api?p=2" to """{"items":[{"name":" 星海 ","author":"小舟","url":"/b","tags":["奇幻","冒险"]}]}"""))
            .execute("search") as Map<*, *>
        val book = (result["items"] as List<*>).single() as Map<*, *>
        assertEquals("星海", book["name"]); assertEquals("奇幻,冒险", book["kind"])
    }
    @Test fun postOptionsAndKeyEncoding() {
        val source = mapOf("searchUrl" to """/search,{"method":"POST","body":"q={{key}}&p={{page}}","headers":{"X-Source":"yes"}}""",
            "ruleSearch" to mapOf("bookList" to "$.items[*]", "name" to "$.name", "bookUrl" to "$.url"))
        engine(source, request = { url, method, headers, body ->
            assertEquals("$base/search", url); assertEquals("POST", method)
            assertEquals("q=%E6%98%9F%E6%B5%B7&p=1", body!!.toString(Charsets.UTF_8)); assertEquals("yes", headers["X-Source"])
            SourceReply(url, "{\"items\":[]}")
        }).execute("search", key = "星海")
    }
    @Test fun bracketedSearchParametersPreserveBothScriptsAndPage() {
        val source = mapOf("searchUrl" to "/books?page={{page}}&q%5Btitle_cont%5D={{key}}",
            "ruleSearch" to mapOf("bookList" to "$.items[*]", "name" to "$.name", "bookUrl" to "$.url"))
        for (word in listOf("龙与后记", "龍與後記")) {
            engine(source, request = { url, _, _, _ ->
                val parsed = java.net.URI(url)
                assertEquals("page=3&q[title_cont]=$word", parsed.query)
                SourceReply(url, "{\"items\":[]}")
            }).execute("search", key = word, page = 3)
        }
    }
    @Test fun searchPageTemplateKeepsItsFiltersWhenHtmlPagerOmitsThem() {
        val source = mapOf("searchUrl" to "/books?q={{key}}&page={{page}}",
            "ruleSearch" to mapOf("bookList" to ".book", "name" to "a@text", "bookUrl" to "a@href"))
        val requested = mutableListOf<String>()
        val runner = engine(source, request = { url, _, _, _ ->
            requested.add(url)
            SourceReply(url, """<div class="book"><a href="/book/one">星海</a></div>
                <nav class="pagination"><a rel="next" href="/books?page=2">下一页</a></nav>""")
        })
        val first = runner.execute("search", key = "星海") as Map<*, *>
        assertNull(first["nextUrl"])
        assertEquals(true, first["hasMore"])
        runner.execute("search", key = "星海", page = 2)
        assertEquals(listOf("$base/books?q=%E6%98%9F%E6%B5%B7&page=1", "$base/books?q=%E6%98%9F%E6%B5%B7&page=2"), requested)
    }
    @Test fun inferredCursorRetainingSearchFiltersIsStillFollowed() {
        val source = mapOf("searchUrl" to "/books?q={{key}}&page={{page}}",
            "ruleSearch" to mapOf("bookList" to ".book", "name" to "a@text", "bookUrl" to "a@href"))
        val runner = engine(source, request = { url, _, _, _ -> SourceReply(url,
            """<div class="book"><a href="/book/one">星海</a></div>
                <a rel="next" href="/books?q=%E6%98%9F%E6%B5%B7&amp;cursor=next">下一页</a>""") })
        val result = runner.execute("search", key = "星海") as Map<*, *>
        assertEquals("$base/books?q=%E6%98%9F%E6%B5%B7&cursor=next", result["nextUrl"])
    }
    @Test fun defaultRulesXPathFallbackAndRegex() {
        val rules = engine()
        val html = "<div class='book'><a href='/one'>第一本</a><span>作者：小舟</span></div>"
        assertEquals("第一本", rules.evaluate("class.missing@text||class.book@tag.a@text", html))
        assertEquals("小舟", rules.evaluate("tag.span@text##作者：##", html))
        assertEquals("/one", rules.evaluate("//a/@href", html))
        assertEquals("第一本", rules.evaluate("@XPath://a/text()", html))
    }
    @Test fun tocPaginationVolumesAndRelativePages() {
        val source = mapOf("ruleToc" to mapOf("chapterList" to ".toc li", "chapterName" to "@text", "chapterUrl" to "a@href",
            "isVolume" to "@data-volume", "nextTocUrl" to "a.next@href"))
        val result = engine(source, mapOf(
            "$base/toc" to "<ul class='toc'><li data-volume='true'>第一卷</li><li><a href='/c1'>第一章</a></li></ul><a class='next' href='/toc2'>下一页</a>",
            "$base/toc2" to "<ul class='toc'><li><a href='/c2'>第二章</a></li></ul><a class='next' href='/toc'>循环链接</a>",
        )).execute("toc", "$base/toc") as List<*>
        assertEquals(3, result.size); assertEquals(true, (result[0] as Map<*, *>)["isVolume"])
        assertEquals("$base/c2", (result[2] as Map<*, *>)["url"])
    }
    @Test fun contentKeepsInlineImagesAndDoesNotConsumeNextChapter() {
        val source = mapOf("ruleContent" to mapOf("content" to "#content@html", "nextContentUrl" to "a.next@href"))
        val result = engine(source, mapOf(
            "$base/c1" to "<div id='content'><p>第一段。</p><img data-src='/images/one.jpg'><p>第二段。</p></div><a class='next' href='/c2'>下一章</a>",
        )).execute("content", "$base/c1", chapter = mapOf("nextChapterUrl" to "$base/c2")) as String
        assertTrue(result.contains("第一段。\n\n<!--image-->$base/images/one.jpg<!--image-->\n\n第二段。"))
    }
    @Test fun contentHtmlAndJsonRules() {
        val html = engine(mapOf("ruleContent" to mapOf("content" to "#c@html")), mapOf("$base/a" to "<div id='c'><p>一</p><p>二</p></div>"))
        assertEquals("一\n\n二", html.execute("content", "$base/a"))
        val json = engine(mapOf("ruleContent" to mapOf("content" to "$.body")), mapOf("$base/b" to "{\"body\":\"一\\n二\"}"))
        assertEquals("一\n\n二", json.execute("content", "$base/b"))
    }
    @Test fun exploreListsAreNotBuiltInAndDoNotFetch() {
        assertTrue((engine().execute("explores") as List<*>).isEmpty())
        val choices = engine(mapOf("exploreUrl" to "最近::/new?page={{page}}&&完结::/done" )).execute("explores") as List<*>
        assertEquals(2, choices.size); assertEquals("最近", (choices[0] as Map<*, *>)["title"])
    }
    @Test fun scriptedExploreListsRetainIndividualHtmlRows() {
        val source = mapOf("ruleExplore" to mapOf(
            "bookList" to "@js:var rows=java.getElement('class.books@tag.li'); if(!rows.length){rows=[result];} rows",
            "name" to "class.title@text", "author" to "class.author@ownText", "bookUrl" to "a@href"))
        val html = """<ul class="books"><li><a class="title" href="/one">星海</a><span class="author">作者：小舟</span></li>
            <li><a class="title" href="/two">春日</a><span class="author">作者：小雨</span></li></ul>"""
        val result = engine(source, mapOf("$base/list" to html)).execute("explore", "$base/list") as Map<*, *>
        val rows = result["items"] as List<*>
        assertEquals(listOf("星海", "春日"), rows.map { (it as Map<*, *>)["name"] })
        assertEquals(listOf("小舟", "小雨"), rows.map { (it as Map<*, *>)["author"] })
    }
    @Test fun scriptsAreBoundedAndHaveNoJvmReflection() {
        val runner = engine()
        assertEquals("undefined", runner.evaluate("@js:typeof Packages", ""))
        assertEquals("undefined", runner.evaluate("@js:typeof java.getClass", ""))
        assertEquals("值", runner.evaluate("@js:java.put('x','值'); java.getStr('x')", ""))
        val failure = runCatching { runner.evaluate("@js:while(true){}", "") }.exceptionOrNull()
        assertNotNull(failure)
    }
    @Test fun cancellationHappensBeforeAnyRequest() {
        val runner = BookSourceEngine(mapOf("bookSourceUrl" to base), SourceRun(fetch = { _, _, _, _ -> error("must not run") }, cancelled = { true }))
        assertTrue(runCatching { runner.execute("content", "$base/c") }.exceptionOrNull() is CancellationException)
    }
    @Test fun selectorsAndTemplatesDoNotSplitQuotedAtCharacters() {
        assertEquals(listOf("a[href='hello@world']", "href"), BookSourceEngine.splitRules("a[href='hello@world']@href", "@"))
        assertEquals("x", engine().evaluate("@js:JSON.parse('{\"name\":\"x\"}').name", ""))
        assertEquals("完成", engine().evaluate("{{'完'+'成'}}", ""))
    }

    @Test fun loginFormUsesLegadoFieldNamesDefaultsActionsAndIsolatedState() {
        val state = SourceState()
        val source = mapOf("bookSourceUrl" to base, "loginUi" to """[{"name":"账号","type":"text"},{"name":"密码","type":"password"},{"name":"方式","type":"select","chars":["甲","乙"]},{"name":"按钮","type":"button","viewName":"'验证'","action":"check()"}]""",
            "loginUrl" to "@js:function login(){source.putLoginHeader(JSON.stringify({'X-User':source.getLoginInfoMap().get('账号')}));} function check(){source.put('checked',result['方式']);}")
        fun runner() = BookSourceEngine(source, SourceRun(state = state, fetch = { _, _, _, _ -> error("Offline fixture") }))
        val ui = runner().execute("loginUi") as Map<*, *>
        assertEquals("甲", (ui["info"] as Map<*, *>)["方式"])
        assertEquals("验证", ((ui["rows"] as List<*>).last() as Map<*, *>)["label"])
        runner().execute("login", book = mapOf("loginInfo" to mapOf("账号" to "fixture-user", "密码" to "fixture-value", "方式" to "乙")))
        assertTrue(state.get("login", "header").contains("fixture-user"))
        runner().execute("login", key = "check()", book = mapOf("loginInfo" to mapOf("方式" to "乙")))
        assertEquals("乙", state.get("source", "checked"))
        assertEquals("", SourceState().get("login", "header"))
    }

    @Test fun inlineDataImagesRetainBytesAndDoNotIssueNetworkRequests() {
        val runner = engine()
        val data = "data:image/png;base64,AQIDBA=="
        assertEquals(data, BookSourceEngine.absolute(data, base))
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), runner.image(data, false))
        assertEquals("", BookSourceEngine.absolute("data:image/svg+xml;base64,PHN2Zz4=", base))
        assertTrue(BookSourceEngine.markup("<p>图</p><img src='$data'>", base).contains("<!--image-->$data<!--image-->"))
        assertEquals("$base/章节/第一话%2F上", BookSourceEngine.absolute("/章节/第一话%2F上", base))
        assertEquals("$base/章节/第一话%2F上", SourceNetwork.url("$base/章节/第一话%2F上").toString())
        assertEquals("$base/books?page=2", BookSourceEngine.absolute("?page=2", "$base/books?page=1"))
    }

    @Test fun illustrationOptionsKeepExplicitHeadersAndWhitespaceDelimiter() {
        val raw = "/images/a.png , {\"headers\":{\"Referer\":\"$base/image-gateway\",\"X-Image\":\"fixture\"}}"
        val address = BookSourceEngine.absolute(raw, "$base/chapter")
        assertEquals("$base/images/a.png,{\"headers\":{\"Referer\":\"$base/image-gateway\",\"X-Image\":\"fixture\"}}", address)
        val bytes = byteArrayOf(1, 2, 3)
        val runner = engine(request = { url, _, headers, _ ->
            assertEquals("$base/images/a.png", url)
            assertEquals("$base/image-gateway", headers["Referer"])
            assertEquals("fixture", headers["X-Image"])
            SourceReply(url, "", data = bytes)
        })
        assertArrayEquals(bytes, runner.image(address, false, "$base/chapter"))
    }

    @Test fun imageChapterBaseDoesNotInventARefererHeader() {
        val bytes = byteArrayOf(1, 2, 3)
        val runner = engine(request = { url, _, headers, _ ->
            assertEquals("$base/images/a.png?size=large&v=2", url)
            assertTrue(headers.keys.none { it.equals("Referer", true) })
            SourceReply(url, "", data = bytes)
        })
        assertArrayEquals(bytes, runner.image("/images/a.png?size=large&v=2", false, "$base/chapter"))
    }
}
