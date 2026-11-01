package org.mewx.wenku8_flutter

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import javax.net.ssl.SSLException

/** Self-authored, offline fixtures. No imported third-party content sources. */
class SourceHostApiTest {
    private val base = "https://fixture.invalid"
    private fun engine(extra: Map<String, Any?> = emptyMap(), state: SourceState = SourceState(),
                       fetch: (String, String, Map<String, String>, ByteArray?) -> SourceReply = { url, _, _, _ -> SourceReply(url, "fixture") }) =
        BookSourceEngine(mapOf("bookSourceUrl" to base, "bookSourceName" to "自编测试") + extra, SourceRun(fetch = fetch, state = state))
    private fun BookSourceEngine.script(code: String) = evaluate("@js:$code", "fixture")

    @Test fun ajaxSoftFailureAndConnectKeepTheOuterBaseAndSafeErrorShape() {
        val host = engine(fetch = { _, _, _, _ -> throw SSLException("account=must-not-appear") })
        val error = host.script("java.ajax('https://helper.invalid/private')").toString()
        assertTrue(error.contains("javax.net.ssl.SSLException")); assertFalse(error.contains("account=")); assertFalse(error.contains("helper.invalid"))
        assertEquals("200|string|https://helper.invalid/private", host.script("var r=java.connect('https://helper.invalid/private');r.code()+'|'+typeof r.url()+'|'+r.url()"))
        assertEquals(base, host.script("baseUrl"))
        assertTrue(runCatching { host.script("java.get('https://helper.invalid/private',null)") }.isFailure)
    }

    @Test fun httpErrorResponsesRemainReadableWithoutChangingTheOuterUrl() {
        val host = engine(fetch = { _, _, _, _ -> SourceReply("https://helper.invalid/final", "denied", 403,
            mapOf("X-Trace" to listOf("one", "two")), message = "Forbidden") })
        assertEquals("403|Forbidden|denied|two|one,two|/final", host.script("""
            var r=java.connect('https://helper.invalid/start');
            r.code()+'|'+r.message()+'|'+r.errorBody().string()+'|'+r.headers().get('x-trace')+'|'+
              r.headers().values('X-Trace').get(0)+','+r.headers().values('X-Trace').get(1)+'|'+r.raw().request().url().getPath()
        """))
        assertEquals(base, host.script("baseUrl"))
    }

    @Test fun jsoupConvenienceRequestsUseTheirOwnHeadersNoRedirectAndTimeout() {
        val calls = mutableListOf<Triple<String, Map<String, String>, SourceHttpOptions>>()
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base, "header" to "{\"Authorization\":\"not-inherited\"}"),
            SourceRun(fetch = { _, _, _, _ -> error("Use options") }, fetchOptions = { url, method, headers, _, options ->
                calls.add(Triple(method, headers, options))
                SourceReply(url, "<p>fixture</p>", 302, mapOf("Location" to listOf("/next")))
            }))
        assertEquals("302|/get|fixture|GET", host.script("var r=java.get('$base/get',{'X-Fixture':'yes'},1234);r.statusCode()+'|'+r.url().getPath()+'|'+r.parse().text()+'|'+r.method()"))
        assertEquals("yes", calls.single().second["X-Fixture"])
        assertFalse(calls.single().second.containsKey("Authorization"))
        assertFalse(calls.single().third.followRedirects)
        assertEquals(1234L, calls.single().third.callTimeout)
        assertTrue(calls.single().third.cookieJar)
        host.script("java.post('$base/post','body','{\"X-Fixture\":\"post\"}',2345).body();java.head('$base/head',null,3456).statusCode()")
        assertEquals(listOf("GET", "POST", "HEAD"), calls.map { it.first })
        assertEquals("post", calls[1].second["X-Fixture"])
        assertEquals(3456L, calls[2].third.callTimeout)
        assertTrue(runCatching { host.script("java.get('$base/get',{'X-Bad':null})") }.isFailure)
        assertTrue(runCatching { host.script("java.get('$base/get',[1,2])") }.isFailure)
    }

    @Test fun ajaxAllIsConcurrentOrderedAndAnArray() {
        val both = CountDownLatch(2)
        val host = engine(fetch = { url, _, _, _ ->
            both.countDown(); check(both.await(2, TimeUnit.SECONDS)) { "Batch requests were serialized" }
            if (url.endsWith("/one")) Thread.sleep(25)
            SourceReply(url, url.substringAfterLast('/'))
        })
        assertEquals("2|one,two|string", host.script("var rows=java.ajaxAll(['$base/one','$base/two']);rows.length+'|'+rows.map(function(r){return r.body()}).join(',')+'|'+typeof rows[0].url()"))
    }

    @Test fun batchUsesTheExplicitTestTimeoutAndDoesNotSoftenFailures() {
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base), SourceRun(fetch = { _, _, _, _ -> error("Use options") },
            fetchOptions = { url, _, _, _, options ->
                assertEquals(456L, options.callTimeout)
                if (url.endsWith("/bad")) throw java.io.IOException("fixture failure")
                SourceReply(url, "ok")
            }))
        assertEquals("ok", host.script("java.ajaxTestAll(['$base/one'],456,true)[0].body()"))
        assertTrue(runCatching { host.script("java.ajaxTestAll(['$base/bad'],456,true)") }.isFailure)
    }

    @Test fun batchCancellationCancelsAllRunningWork() {
        val started = CountDownLatch(2)
        val finished = CountDownLatch(2)
        lateinit var run: SourceRun
        run = SourceRun(fetch = { url, _, _, _ ->
            try { started.countDown(); while (true) { run.check(); Thread.sleep(10) }; @Suppress("UNREACHABLE_CODE") SourceReply(url, "never") }
            finally { finished.countDown() }
        })
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base), run)
        var failed = false
        val worker = kotlin.concurrent.thread { failed = runCatching { host.script("java.ajaxAll(['$base/one','$base/two'])") }.isFailure }
        assertTrue(started.await(2, TimeUnit.SECONDS)); run.cancel()
        worker.join(2000)
        assertFalse(worker.isAlive); assertTrue(failed); assertTrue(finished.await(2, TimeUnit.SECONDS))
    }

    @Test fun importScriptReturnsTextAndOnlyRunsWhenExplicitlyEvaluated() {
        val count = AtomicInteger()
        val state = SourceState()
        val host = engine(state = state, fetch = { url, _, _, _ -> count.incrementAndGet(); SourceReply(url, "var importedValue='自编脚本';") })
        assertEquals("undefined|自编脚本", host.script("var text=java.importScript('$base/library.js');var before=typeof importedValue;eval(text);before+'|'+importedValue"))
        assertEquals("var importedValue='自编脚本';", host.script("java.cacheFile('$base/library.js',60)"))
        assertEquals(1, count.get())
        state.put("script-expiry", "$base/library.js", "1")
        host.script("sourceApi.cacheFile('$base/library.js',60)")
        assertEquals(2, count.get())
        assertEquals(base, host.script("baseUrl"))
        assertTrue(runCatching { host.script("java.importScript('/private/device-file')") }.isFailure)
    }

    @Test fun sourceInheritsHelpersAndUsesTheSameSourceVariables() {
        val state = SourceState()
        val host = engine(state = state)
        assertEquals("fixture|fixture|source-value|global-value|true", host.script("""
            source.put('key','source-value');java.put('global','global-value');source.setVariable('custom');source.setVariable(null);
            source.ajax('$base/one')+'|'+sourceApi.connect('$base/two').body()+'|'+source.get('key')+'|'+java.get('global')+'|'+(source.getVariable()==='')
        """))
        assertEquals(SourceNetwork.USER_AGENT, host.script("source.getHeaderMap().get('User-Agent')"))
        assertEquals("7|undefined", host.script("source.evalJS('var hidden=1;({number:input})',{input:7}).number+'|'+typeof hidden"))
        assertEquals("undefined|7|object", host.script("typeof hidden+'|'+source.evalJS('input',{input:7})+'|'+typeof sourceApi"))
    }

    @Test fun loginDefaultsInitializeWithoutOpeningAFormAndGuardReentry() {
        val source = mapOf("loginUi" to "@js:var saved=source.getLoginInfoMap();JSON.stringify([{name:'route',type:'text',default:'public'},{name:'Login',type:'button'}])")
        val state = SourceState()
        val host = engine(source, state)
        assertEquals("public|1", host.script("var m=source.getLoginInfoMap();m.get('route')+'|'+m.size()"))
        assertTrue(state.get("login", "info").contains("public"))
        assertEquals("next|next", host.script("var m=source.getLoginInfoMap();m.put('route','next');source.putLoginInfo(JSON.stringify(m));source.getLoginInfoMap().get('route')+'|'+m.route"))
    }

    @Test fun bookAndChapterVariablesAndMetadataSurviveTheFlutterBoundary() {
        val state = SourceState()
        val tocSource = mapOf("ruleToc" to mapOf("chapterList" to "li", "chapterName" to "a@text", "chapterUrl" to "a@href",
            "isVolume" to "@data-volume", "isVip" to "@data-vip", "isPay" to "@data-pay", "updateTime" to "@data-info"))
        val rows = engine(tocSource, state, fetch = { url, _, _, _ -> SourceReply(url,
            "<ul><li data-volume='true'><a>卷一</a></li><li data-vip='true' data-pay='true' data-info='自编标签'><a href='/one'>第一章</a></li></ul>") })
            .execute("toc", "$base/toc", book = mapOf("bookUrl" to "$base/book")) as List<*>
        assertEquals(1, (rows[1] as Map<*, *>)["index"])
        val bodySource = mapOf("ruleContent" to mapOf("content" to """@js:
            book.putCustomVariable('自编变量');book.putVariable('drop','old');var deleted=book.putVariable('drop',null);
            book.variableMap.put('map','value');book.variableMap.direct='direct';
            chapter.putVariable('token','chapter');chapter.setImgUrl('/figure.png');
            deleted+'|'+book.getCustomVariable()+'|'+book.getVariable('drop')+'|'+JSON.parse(book.variable).map+'|'+book.variableMap.get('direct')+'|'+
              chapter.getIndex()+'|'+chapter.getIsVip()+'|'+chapter.getIsPay()+'|'+chapter.getTag()+'|'+chapter.primaryStr()+'|'+chapter.getAbsoluteURL()
        """))
        val result = engine(bodySource, state).execute("content", "$base/one", book = mapOf("bookUrl" to "$base/book"),
            chapter = mapOf("url" to "$base/one", "title" to "第一章", "index" to 0))
        assertEquals("true|自编变量||value|direct|1|true|true|自编标签|$base/book$base/one|$base/one", result)
        assertEquals("chapter", state.get("chapter:$base/one", "token"))
        assertEquals("value", state.get("book:$base/book", "map"))
        assertFalse(state.contains("book:$base/book", "drop"))
        val isolated = engine(bodySource).execute("content", "$base/one", book = mapOf("bookUrl" to "$base/other"), chapter = mapOf("url" to "$base/one"))
        assertFalse(isolated.toString().contains("自编标签"))
    }

    @Test fun textHelpersMatchUrlBase64FlagsAndHtmlContracts() {
        val host = engine()
        assertEquals("中文|中文", host.script("java.base64Decode(java.base64Encode('中文'))+'|'+java.base64Decode(java.base64Encode('中文',11),8)"))
        assertEquals("a b", host.script("java.base64Decode('YSBi','UTF-8')"))
        assertEquals("😀|😀|true", host.script("java.base64Decode('8J-YgA==')+'|'+java.base64Decode('8J-YgA==',8)+'|'+(java.base64DecodeToByteArray(null)===null)"))
        assertEquals("https://fixture.invalid|/book|中文|two", host.script("var u=java.toURL('/book?q=%E4%B8%AD%E6%96%87&same=one&same=two','$base');u.origin+'|'+u.pathname+'|'+u.searchParams.get('q')+'|'+u.searchParams.get('same')"))
        assertEquals("1970-01-01 08:00", host.script("java.timeFormatUTC(0,'yyyy-MM-dd HH:mm',28800000)"))
        assertEquals("1970-01-01 08:00", host.script("java.timeFormatUTC('0','yyyy-MM-dd HH:mm','28800000')"))
        assertEquals("a+b|", host.script("java.encodeURI('a b')+'|'+java.encodeURI('abc','invalid-charset-fixture')"))
        // Pinned upstream JVM regex behavior preserves the initial formatter
        // indent twice; the reader independently applies its own indentation.
        assertEquals("　　　　第一段\n　　<img src=\"$base/img.png\">", host.script("java.htmlFormat('<p>第一段</p><img src=\"/img.png\">','$base')"))
        assertEquals("value", host.script("java.log('value')"))
    }

    @Test fun cacheTypedBinaryFileAndMemoryApisHonorExpiryAndIsolation() {
        val state = SourceState()
        val host = engine(state = state)
        assertEquals("true|17|17|17|17", host.script("cache.get('missing')===null;cache.put('n','17');(cache.get('missing')===null)+'|'+cache.getInt('n')+'|'+cache.getLong('n')+'|'+cache.getDouble('n')+'|'+cache.getFloat('n')"))
        assertEquals("true|forever", host.script("cache.put('key','expired',-1);var before=cache.get('key');cache.put('key','forever');(before===null)+'|'+cache.get('key')"))
        assertEquals("disk|memory|disk", host.script("cache.put('key','disk');cache.putMemory('key','memory');var value=cache.get('key',true)+'|'+cache.get('key');cache.deleteMemory('key');value+'|'+cache.get('key')"))
        assertEquals("memory-object", host.script("cache.putMemory('obj',{text:'memory-object'});cache.getFromMemory('obj').text"))
        assertEquals("ABC|true|file", host.script("cache.put('bytes',java.strToBytes('ABC'));cache.putFile('expired','no',-1);cache.putFile('file','file');java.bytesToStr(cache.getByteArray('bytes'))+'|'+(cache.getFile('expired')===null)+'|'+cache.getFile('file')"))
        assertEquals("true|true|true", host.script("cache.delete('key');cache.delete('bytes');cache.delete('file');(cache.get('key')===null)+'|'+(cache.getByteArray('bytes')===null)+'|'+(cache.getFile('file')===null)"))
        val restored = SourceState().apply { restore(state.snapshot()) }
        assertEquals("true", engine(state = restored).script("String(cache.getFromMemory('obj')===null)"))
        assertNull(SourceState().memory("obj"))
    }

    @Test fun sourceEvalUsesSourceVariablesAndBaseRatherThanTheActiveChapter() {
        val state = SourceState()
        val source = mapOf("ruleContent" to mapOf("content" to "@js:source.evalJS(\"java.put('scope','source');baseUrl\")+'|'+source.get('scope')+'|'+chapter.getVariable('scope')"))
        assertEquals("$base|source|", engine(source, state).execute("content", "$base/chapter",
            book = mapOf("bookUrl" to "$base/book"), chapter = mapOf("url" to "$base/chapter")))
        assertEquals("source", state.get("source", "scope"))
        assertFalse(state.contains("chapter:$base/chapter", "scope"))
    }

    @Test fun failedBatchCancelsSiblingCallsWithoutCancellingTheCaller() {
        val both = CountDownLatch(2)
        val cancelled = CountDownLatch(1)
        lateinit var run: SourceRun
        run = SourceRun(fetch = { url, _, _, _ ->
            val unregister = run.onCancel { if (url.endsWith("/waiting")) cancelled.countDown() }
            try {
                both.countDown(); check(both.await(2, TimeUnit.SECONDS))
                if (url.endsWith("/bad")) throw java.io.IOException("fixture error")
                while (true) { run.check(); Thread.sleep(10) }
                @Suppress("UNREACHABLE_CODE") SourceReply(url, "never")
            } finally { unregister() }
        })
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base), run)
        assertEquals("fallback", host.script("try{java.ajaxAll(['$base/bad','$base/waiting']);'unexpected'}catch(e){'fallback'}"))
        assertTrue(cancelled.await(2, TimeUnit.SECONDS)); run.check()
        assertEquals("still-active", host.script("'still-active'"))
    }
    @Test fun nestedRequestScriptsDoNotOverwriteTheCallingRulesBindings() {
        val host = engine()
        val nested = "$base/helper,{\"bodyJs\":\"result+'-processed'\"}"
        val argument = org.mewx.wenku8_flutter.legado.js.SourceGson.gson.toJson(nested)
        assertEquals("fixture|fixture|fixture-processed|$base", host.script("var reply=java.ajax($argument);result+'|'+src+'|'+reply+'|'+baseUrl"))
    }
    @Test fun dynamicHeadersUseSourceVariablesNotChapterVariables() {
        val state = SourceState().apply { put("source", "token", "source-token"); put("chapter:$base/chapter", "token", "chapter-token") }
        val source = mapOf("header" to "@js:JSON.stringify({'X-Token':java.get('token')})",
            "ruleContent" to mapOf("content" to "p@text"))
        var token = ""
        val host = engine(source, state, fetch = { url, _, headers, _ -> token = headers["X-Token"].orEmpty(); SourceReply(url, "<p>自编正文</p>") })
        assertEquals("自编正文", host.execute("content", "$base/chapter", chapter = mapOf("url" to "$base/chapter")))
        assertEquals("source-token", token)
    }
    @Test fun entityMapPresenceEmptySerializationKindsAndChapterNamesAreUsable() {
        val source = mapOf("ruleContent" to mapOf("content" to """@js:
            var unset=book.getVariable()===null;
            book.putVariable('only','value');var present='only' in book.getVariableMap();book.putVariable('only',null);
            var empty=book.getVariable();book.setVariable(null);
            unset+'|'+present+'|'+empty+'|'+(book.variable===null)+'|'+book.getKindList().size()+'|'+book.getKindList().get(0)+'|'+chapter.getFileName()+'|'+chapter.getFontName()
        """))
        val title = "自编标题"
        val md5 = java.security.MessageDigest.getInstance("MD5").digest(title.toByteArray()).joinToString("") { "%02x".format(it) }.substring(8,24)
        assertEquals("true|true|{}|true|3|12万字|00003-$md5.nb|00003-$md5.ttf", engine(source).execute("content", "$base/one",
            book = mapOf("bookUrl" to "$base/book", "kind" to "奇幻,冒险", "wordCount" to "12万字"),
            chapter = mapOf("url" to "$base/one", "title" to title, "index" to 3)))
    }
}
