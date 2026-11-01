package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceScriptCompatibilityTest {
    private val base = "https://fixture.invalid"
    private fun engine(source: Map<String, Any?>, state: SourceState = SourceState()) =
        BookSourceEngine(mapOf("bookSourceUrl" to base, "bookSourceName" to "自编测试") + source,
            SourceRun(state = state, fetch = { _, _, _, _ -> error("Offline fixture must not fetch") }))

    private val main = """
        var config={bookSourceUrl:'https://fixture.invalid',bookSourceName:'自编测试',
          exploreUrl:[{title:'分类',url:'/list'}]};
        function search(key,page){return [{name:key+' '+page,bookUrl:baseUrl+'/book',author:'作者：自编作者',
          variable:JSON.stringify({searchKey:key}),latestChapterTitle:'第二章'}];}
        function explore(url,page){return search(url,page);}
        function getBookInfo(book){return {name:'完整书名',intro:'自编简介',tocUrl:baseUrl+'/toc',
          kind:'奇幻,冒险',variable:{detailKey:'详情变量'}};}
        function getChapters(book){return [
          {title:'第一卷',url:'第一卷',isVolume:true},
          {title:'第一章',url:'/chapter/1',variable:JSON.stringify({chapterKey:'章节变量'})},
          {title:'第二章',url:'/chapter/2'}];}
        function getContent(chapter,book,nextChapterUrl){return '自编正文 '+chapter.title+' '+
          sourceApi.getKey()+' '+java.get('detailKey')+' '+java.get('chapterKey');}
    """.trimIndent()

    @Test fun rawScriptConfigUsesNativeNamesAndNeverUsesSavedSessions() {
        val parsed = engine(emptyMap()).execute("inspectScript", key = main) as Map<*, *>
        assertEquals("自编测试", parsed["bookSourceName"])
        assertEquals(main, parsed["mainJs"])
        assertTrue(parsed["exploreUrl"] is String)
        assertFalse(parsed.containsKey("ruleSearch"))
        val failure = runCatching { engine(emptyMap()).execute("inspectScript", key = main + "\njava.ajax('https://fixture.invalid/no');") }
        assertTrue(failure.isFailure)
    }

    @Test fun scriptSourceSearchDetailVolumesAndContentUseSameEntryPoints() {
        val state = SourceState()
        val source = mapOf("mainJs" to main)
        val found = engine(source, state).execute("search", key = "星海", page = 2) as Map<*, *>
        val book = (found["items"] as List<*>).single() as Map<*, *>
        assertEquals("星海 2", book["name"])
        assertEquals("自编作者", book["author"])
        assertEquals("第二章", book["lastChapter"])
        @Suppress("UNCHECKED_CAST")
        val detail = engine(source, state).execute("detail", "$base/book", book = book as Map<String, Any?>) as Map<String, Any?>
        assertEquals("完整书名", detail["name"])
        assertEquals("自编简介", detail["intro"])
        val toc = engine(source, state).execute("toc", "$base/toc", book = detail) as List<*>
        assertEquals(true, (toc[0] as Map<*, *>)["isVolume"])
        assertEquals("第一卷", (toc[0] as Map<*, *>)["url"])
        val first = toc[1] as Map<*, *>
        assertEquals("第一卷", first["volumeTitle"])
        assertEquals("$base/chapter/1", first["url"])
        val content = engine(source, state).execute("content", first["url"].toString(), book = detail,
            chapter = mapOf("title" to first["title"], "url" to first["url"], "nextChapterUrl" to "$base/chapter/2"))
        assertEquals("自编正文 第一章 $base 详情变量 章节变量", content)
        assertEquals("星海", state.get("book:$base/book", "searchKey"))
    }

    @Test fun optionalDetailCanMutateBookAndStringifiedResultsAreAccepted() {
        val source = mapOf("mainJs" to """
            function search(key,page){return JSON.stringify([{name:key,bookUrl:'b'}]);}
            function getBookInfo(book){book.intro='自编简介';}
        """)
        val rows = engine(source).execute("search", key = "小舟") as Map<*, *>
        assertEquals("小舟", (((rows["items"] as List<*>).single()) as Map<*, *>)["name"])
        val detail = engine(source).execute("detail", "$base/b", book = mapOf("name" to "小舟", "bookUrl" to "$base/b")) as Map<*, *>
        assertEquals("小舟", detail["name"])
        assertEquals("自编简介", detail["intro"])
        assertEquals("$base/b", detail["tocUrl"])
        val missing = engine(mapOf("mainJs" to "function search(){}"))
            .execute("detail", "$base/b", book = mapOf("name" to "原书名", "bookUrl" to "$base/b")) as Map<*, *>
        assertEquals("原书名", missing["name"])
    }

    @Test fun jsonNormalizationHonorsToJsonAndRejectsCycles() {
        val source = mapOf("mainJs" to "function search(key,page){return {toJSON:function(){return [{name:key+page,bookUrl:'b'}];}};}")
        val rows = engine(source).execute("search", key = "星", page = 2) as Map<*, *>
        assertEquals("星2", (((rows["items"] as List<*>).single()) as Map<*, *>)["name"])
        assertTrue(runCatching { engine(mapOf("mainJs" to "function search(){var a={};a.x=a;return a;}"))
            .execute("search", key = "星") }.isFailure)
    }

    @Test fun bundledUpstreamCryptoJsAndCompiledScriptsRetainIsolatedScopes() {
        val code = """var counter=0; function search(key,page){return [{name:CryptoJS.MD5(key).toString()+' '+(++counter),bookUrl:'b'}];}"""
        repeat(2) {
            val result = engine(mapOf("mainJs" to code)).execute("search", key = "hello") as Map<*, *>
            assertEquals("5d41402abc4b2a76b9719d911017c592 1", (((result["items"] as List<*>).single()) as Map<*, *>)["name"])
        }
        val html = engine(mapOf("mainJs" to "function getContent(){return '<p>一</p><img src=\"/image.png\"><p>二</p>';}"))
            .execute("content", "$base/chapter", chapter = mapOf("url" to "$base/chapter")) as String
        assertTrue(html.contains("<!--image-->$base/image.png<!--image-->"))
        val strict = engine(emptyMap()).execute("inspectScript", key = "'use strict';\n" + main) as Map<*, *>
        assertEquals(main.let { "'use strict';\n$it" }, strict["mainJs"])
    }

    private val loginJs = """
        function loginUi(state){return {rows:state.step==='code'?[
          {type:'label',name:'输入验证码'},
          {key:'code',name:'验证码',type:'text',hint:'6位数字'},
          {name:'登录',type:'button',action:'verify'}]:[
          {key:'phone',name:'手机号',type:'text'},
          {key:'remember',name:'记住登录',type:'toggle',value:'true'},
          {key:'route',name:'线路',type:'select',options:['甲','乙']},
          {name:'发送验证码',type:'button',action:'send',countdown:2}]};}
        function loginAction(action,state,form){
          if(action==='send')return form.phone?{state:{step:'code'}}:{error:{phone:'请输入手机号'}};
          if(action==='verify'&&form.code==='123456')return {login:{name:'fixture'},close:true};
          return {error:{code:'验证码不正确'}};
        }
    """.trimIndent()

    @Test fun upstreamLoginV2StateErrorsAndExplicitLoginCommandsAreIsolated() {
        val state = SourceState()
        val source = mapOf("loginUi" to "{\"version\":2}", "loginUrl" to "@js:$loginJs")
        val ui = engine(source, state).execute("loginUi") as Map<*, *>
        assertEquals(2, ui["version"])
        assertEquals(4, (ui["rows"] as List<*>).size)
        val empty = engine(source, state).execute("login", key = "send", book = mapOf("loginInfo" to emptyMap<String, String>())) as Map<*, *>
        assertEquals("请输入手机号", (empty["error"] as Map<*, *>)["phone"])
        assertEquals("", state.get("login", "info"))
        val next = engine(source, state).execute("login", key = "send", book = mapOf("loginInfo" to mapOf("phone" to "fixture"))) as Map<*, *>
        assertEquals("code", (next["state"] as Map<*, *>)["step"])
        assertEquals(3, (next["rows"] as List<*>).size)
        val done = engine(source, state).execute("login", key = "verify", book = mapOf(
            "loginState" to next["state"], "loginInfo" to mapOf("code" to "123456"))) as Map<*, *>
        assertEquals(true, done["close"])
        assertTrue(state.get("login", "info").contains("fixture"))
        assertEquals("", SourceState().get("login", "info"))
    }

    @Test fun rawScriptConfigDetectsPairedLoginUiFunctions() {
        val parsed = engine(emptyMap()).execute("inspectScript", key = main + "\n" + loginJs) as Map<*, *>
        assertTrue(SourceLoginUi.isV2(parsed["loginUi"]))
        val v2 = engine(mapOf("mainJs" to main + "\n" + loginJs, "loginUi" to parsed["loginUi"]))
            .execute("loginUi") as Map<*, *>
        assertEquals(4, (v2["rows"] as List<*>).size)
    }

    @Test fun pinnedRuntimeSupportsModernSyntaxE4xAndLegacyBlockDeclarations() {
        val runner = engine(emptyMap())
        assertEquals("星海", runner.evaluate("@js:var v={book:{name:'星海'}};v.book?.name??'缺失'", ""))
        assertEquals("星海", runner.evaluate("@js:var v=<books><book>星海</book></books>;v.book.toString()", ""))
        // The pinned upstream normalizer requires the read position to be
        // strictly after the block range; retain that source behavior.
        assertEquals("旧规则", runner.evaluate("@js:if(true){let legacy='旧规则';} legacy", ""))
        assertEquals("自编测试", runner.evaluate("@js:var f=Function('return this.java.getTag()');f()", ""))
        assertEquals(base, runner.evaluate("@js:java.getSource().getKey()", ""))
        assertEquals("undefined", runner.evaluate("@js:typeof Packages", ""))
    }
}
