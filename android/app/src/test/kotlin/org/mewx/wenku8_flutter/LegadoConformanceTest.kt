package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

/** The expected values follow the pinned Legado grammar, not the old prototype. */
class LegadoConformanceTest {
    private val origin = "https://rules.invalid"
    private val rows = "<ul>" + (0..4).joinToString("") { "<li>$it</li>" } + "</ul>"
    private fun engine(source: Map<String, Any?> = emptyMap(), state: SourceState = SourceState(),
        fetch: (String, String, Map<String, String>, ByteArray?) -> SourceReply = { url, _, _, _ -> SourceReply(url, "") }) =
        BookSourceEngine(mapOf("bookSourceUrl" to origin) + source, SourceRun(fetch = fetch, state = state))

    @Test fun defaultIndexRangesAreInclusiveAndCanReverseOrExclude() {
        val e = engine()
        assertEquals("4\n2\n0", e.evaluate("tag.li[-1:0:2]@text", rows))
        assertEquals("1\n2\n3", e.evaluate("tag.li[!0,-1]@text", rows))
        assertEquals("4\n1", e.evaluate("tag.li.-1:1@text", rows))
        assertEquals("0\n2\n4", e.evaluate("@CSS:li:nth-child(odd)@text", rows))
    }
    @Test fun combinationAndInterleavingKeepLegadoOrder() {
        val html = "<a>A</a><a>B</a><b>1</b><b>2</b>"
        assertEquals("A\n1\nB\n2", engine().evaluate("tag.a@text%%tag.b@text", html))
        assertEquals("A\nB\n1\n2", engine().evaluate("tag.a@text&&tag.b@text", html))
        assertEquals("A\nB", engine().evaluate("tag.q@text||tag.a@text", html))
    }
    @Test fun regexBookListsCarryCaptureGroupsIntoFields() {
        val e = engine()
        val items = e.evaluate(":<a href='(.*?)'>(.*?)</a>", "<a href='/a'>甲</a><a href='/b'>乙</a>", elements = true) as List<*>
        assertEquals(2, items.size)
        assertEquals("甲", e.evaluate("$2", items[0]))
        assertEquals("/b", e.evaluate("$1", items[1]))
    }
    @Test fun javascriptCanBeChainedBeforeAndAfterSelectors() {
        assertEquals("星海", engine().evaluate("<js>result.replace('旧名','星海')</js>h1@text<js>result.trim()</js>", "<h1>旧名</h1>"))
        assertEquals("123", engine().evaluate("h1@text##\\D+##", "<h1>第123章</h1>"))
        assertEquals("X", engine().evaluate("h1@text##\\d+##X###", "<h1>abc123def456</h1>"))
    }
    @Test fun jsonFilterOperatorsAndNestedTemplatesAreNotSplit() {
        val json = """{"items":[{"name":"甲","a":1,"b":2},{"name":"乙","a":1,"b":0}]}"""
        assertEquals("甲", engine().evaluate("$.items[?(@.a == 1 && @.b == 2)].name", json))
        assertEquals("书名：甲", engine().evaluate("书名：{$.items[0].name}", json))
        assertEquals("6", engine().evaluate("{{3*2}}", json))
    }
    @Test fun putGetAndBookVariablesSurviveOperationBoundaries() {
        val state = SourceState()
        engine(state = state).evaluate("@put:{\"token\":\"h1@text\"}h1@text", "<h1>已保存</h1>")
        assertEquals("已保存", engine(state = state).evaluate("@get:{token}", ""))
        val source = mapOf("ruleContent" to mapOf("content" to "@js:java.put('chapterToken','章'); book.putVariable('bookToken','书'); source.put('globalToken','源'); '正文'"))
        engine(source, state).execute("content", "$origin/c", book = mapOf("bookUrl" to "$origin/b"), chapter = mapOf("url" to "$origin/c"))
        assertEquals("章", state.get("chapter:$origin/c", "chapterToken"))
        assertEquals("书", state.get("book:$origin/b", "bookToken"))
        assertEquals("源", state.get("source", "globalToken"))
    }
    @Test fun loginFormAndDynamicHeaderUseTheSameEncryptedState() {
        val state = SourceState()
        val source = mapOf(
            "loginUi" to """[{"name":"账号","type":"text"},{"name":"密码","type":"password"}]""",
            "loginUrl" to "@js:function login(){ source.putLoginHeader(JSON.stringify({'Authorization':source.getLoginInfoMap().get('账号')})); }",
            "searchUrl" to "/q", "ruleSearch" to mapOf("bookList" to "$.books"),
            "loginCheckJs" to "if(result.code()!==200) throw 'login'; result",
        )
        assertEquals(2, ((engine(source, state).execute("loginUi") as Map<*, *>)["rows"] as List<*>).size)
        engine(source, state).execute("login", book = mapOf("loginInfo" to mapOf("账号" to "fixture-only", "密码" to "not-a-user-secret")))
        engine(source, state) { url, _, headers, _ ->
            assertEquals("fixture-only", headers["Authorization"])
            SourceReply(url, "{\"books\":[]}")
        }.execute("search")
    }
    @Test fun remoteJsLibMapIsCachedAndAvailableToRules() {
        val state = SourceState(); var calls = 0
        val source = mapOf("jsLib" to "{\"helper\":\"https://rules.invalid/lib.js\"}")
        fun parse() = engine(source, state) { url, _, _, _ -> calls++; SourceReply(url, "function label(x){return '书：'+x;}") }
            .evaluate("@js:label(result)", "甲")
        assertEquals("书：甲", parse()); assertEquals("书：甲", parse()); assertEquals(1, calls)
    }
    @Test fun cryptoHelpersKeepUpstreamNamesAndOverloads() {
        val e = engine()
        assertEquals("900150983cd24fb0d6963f7d28e17f72", e.evaluate("@js:java.md5Encode('abc')", ""))
        assertEquals("3cd24fb0d6963f7d", e.evaluate("@js:java.md5Encode16('abc')", ""))
        assertEquals("测试", e.evaluate("@js:var c=java.createSymmetricCrypto('AES/ECB/PKCS5Padding','1234567890123456'); c.decryptStr(c.encryptBase64('测试'))", ""))
    }
    @Test fun requestOptionsHaveLegadoFormEncodingAndPageAlternatives() {
        val source = mapOf("searchUrl" to """/s<,?p={{page}}>,{"method":"POST","charset":"GBK","body":"q={{key}}"}""", "ruleSearch" to mapOf("bookList" to "$.items"))
        engine(source) { url, method, headers, body ->
            assertEquals("$origin/s?p=2", url); assertEquals("POST", method)
            assertEquals("q=%D0%C7%BA%A3", body!!.toString(Charsets.UTF_8))
            assertEquals("application/x-www-form-urlencoded", headers["Content-Type"])
            SourceReply(url, "{\"items\":[]}")
        }.execute("search", key = "星海", page = 2)
    }
    @Test fun jsonPostAndBodyJsDoNotGetFormEncoded() {
        val source = mapOf("searchUrl" to """/s,{"method":"POST","body":{"q":"{{key}}"},"bodyJs":"JSON.stringify({items:JSON.parse(result).rows})"}""", "ruleSearch" to mapOf("bookList" to "$.items"))
        engine(source) { url, _, headers, body ->
            assertEquals("{\n  \"q\": \"星海\"\n}", body!!.toString(Charsets.UTF_8))
            assertTrue(headers["Content-Type"]!!.startsWith("application/json"))
            SourceReply(url, "{\"rows\":[]}")
        }.execute("search", key = "星海")
    }
    @Test fun nativeNodesAndMutableListsKeepTheirScriptApiAndJsonConversion() {
        val e = engine()
        assertEquals("[\"<p>甲</p>\"]", e.evaluate("@js:JSON.stringify(java.getElements('p'))", "<p>甲</p>"))
        assertEquals("1:乙", e.evaluate("@js:var rows=java.getElements('p'); rows[0]='乙'; rows.size() + ':' + rows[0]", "<p>甲</p>"))
        assertEquals("正文", e.evaluate("@js:org.jsoup.Jsoup.parse(result).select('p').text()", "<p>正文</p>"))
    }
}
