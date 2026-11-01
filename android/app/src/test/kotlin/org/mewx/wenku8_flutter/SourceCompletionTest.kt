package org.mewx.wenku8_flutter

import java.util.Base64
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mewx.wenku8_flutter.legado.SourceResources

/** Self-authored fixtures for the final novel host APIs; no content sources. */
class SourceCompletionTest {
    @get:Rule val temp = TemporaryFolder()
    private val base = "https://completion.invalid"
    private fun run(state: SourceState = SourceState()) = SourceRun(state = state, fetch = { url, _, _, _ -> SourceReply(url, "fetched") })
    private fun host(extra: Map<String, Any?> = emptyMap(), run: SourceRun = run()) = BookSourceEngine(mapOf("bookSourceUrl" to base) + extra, run)
    private fun BookSourceEngine.script(code: String, input: String = "fixture") = evaluate("@js:$code", input)

    @Test fun largeVariableBoundaryAndDeletionFollowRuleDataInterface() {
        val state = SourceState(); val owner = "book:$base/book"
        state.putRuleVariable(owner, "key", "x".repeat(9999)); assertEquals(9999, state.get(owner,"key").length); assertNull(state.getBig(owner,"key"))
        state.putRuleVariable(owner, "key", "x".repeat(10000)); assertFalse(state.contains(owner,"key")); assertEquals(10000,state.ruleVariable(owner,"key").length)
        state.putBig(owner,"key","large"); state.put(owner,"key",""); assertEquals("",state.ruleVariable(owner,"key"))
        state.putRuleVariable(owner,"key",null); assertNull(state.getBig(owner,"key")); assertFalse(state.contains(owner,"key"))
        val row = SourceState(); row.putRuleVariable("row","large","a".repeat(10000)); row.copyRuleVariables("row", state, owner)
        assertEquals(10000,state.ruleVariable(owner,"large").length)
    }

    @Test fun encryptedLargeVariablesSurviveReloadAndMigrateOldInlineState() {
        val key = KeyGenerator.getInstance("AES").apply { init(128) }.generateKey()
        val folder = temp.newFolder()
        fun storage() = SourceBigVariables(folder, seal = { text ->
            val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key)
            Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(text.toByteArray()))
        }, open = { text ->
            val bytes = Base64.getDecoder().decode(text)
            Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE,key,GCMParameterSpec(128,bytes.copyOfRange(0,12))) }
                .doFinal(bytes.copyOfRange(12,bytes.size)).toString(Charsets.UTF_8)
        })
        val value = "自编加密变量".repeat(2000); val owner = "book:$base/book"
        val state = SourceState(storage()).apply { restore(mapOf("$owner\nkey" to value)) }
        assertFalse(state.snapshot().containsValue(value)); assertFalse(folder.listFiles()!!.single().readText().contains("自编加密变量"))
        assertEquals(value,SourceState(storage()).ruleVariable(owner,"key"))
        state.putRuleVariable(owner,"key",null); assertTrue(folder.listFiles()!!.isEmpty())
    }

    @Test fun entityBigMapDisplayTitleAndUpdateArePersistent() {
        val state = SourceState()
        val rules = mapOf("ruleContent" to mapOf("content" to """@js:
            book.putVariable('large','x'.repeat(10000));chapter.setTitle('第壹章\n星海');chapter.setImgUrl('/image');chapter.update();
            book.getVariable('large').length+'|'+book.variableMap.size()+'|'+chapter.getDisplayTitle([{pattern:'壹',replacement:'一',isRegex:false}])
        """))
        assertEquals("10000|0|第一章星海",host(rules,run(state)).execute("content","$base/c",book=mapOf("bookUrl" to "$base/b"),chapter=mapOf("url" to "$base/c")))
        assertEquals(10000,state.getBig("book:$base/b","large")!!.length)
        assertTrue(state.get("chapter-metadata","$base/c").contains("/image"))
    }

    @Test fun sourcePropertiesHelpersAndEnvironmentUseLiveValues() {
        val run = SourceRun(fetch = { url,_,headers,_ -> assertEquals("live",headers["X-Fixture"]);SourceReply(url,"ok") },
            appConfig=mapOf("themeMode" to "2","reader" to mapOf("textSize" to 19),"theme" to mapOf("isNight" to true)),installationId="fixture-install")
        assertEquals("ok|2|19|true|fixture-install|false",host(run=run).script("""
            source.setHeader('{"X-Fixture":"live"}');source.ajax('$base/data')+'|'+java.getThemeMode()+'|'+java.getReadBookConfigMap().get('textSize')+'|'+JSON.parse(java.getThemeConfig()).isNight+'|'+java.androidId()+'|'+source.hasLogin()
        """))
    }

    @Test fun chineseAndChapterNumberHelpersMatchPinnedOriginal() {
        val e = host()
        assertEquals("简体龙书|簡體龍書|第123章|第12章|unchanged", e.script("java.t2s('簡體龍書')+'|'+source.s2t('简体龙书')+'|'+java.toNumChapter('前缀 第一百二十三章 后缀')+'|'+java.toNumChapter('第１２章')+'|'+java.toNumChapter('unchanged')"))
    }
    @Test fun sharedLibraryE4xAndTypeDiagnosticsDoNotExposeValueContents() {
        val types=mutableListOf<String>()
        val e=host(mapOf("jsLib" to "function fixture(){return this.result}"),SourceRun(fetch={u,_,_,_->SourceReply(u,"")},diagnostic={types.add(it)}))
        assertEquals("xml|undefined",e.script("var x=<r><p>xml</p></r>;x.p.toString()+'|'+typeof java.logType('fixture-private-text')"))
        assertEquals(1,types.size);assertFalse(types.single().contains("fixture-private-text"))
    }
    @Test fun analyzerFluentAndSplitRuleOverloadsUseTheSameLiveAnalyzer() {
        val e=host()
        assertEquals("甲|甲,乙|child",e.script("""
            java.setContent('<a href=\"/child\">甲</a><a>乙</a>').setBaseUrl('$base/other');
            var split=java.splitSourceRule('a@text');
            java.getString('a.0@text')+'|'+java.getStringList(split).toArray().join(',')+'|'+java.evalJS('result','child')
        """))
    }

    @Test fun cancelledVerificationOwnerDoesNotCancelOtherCallers() {
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val pool=Executors.newFixedThreadPool(2)
        try {
            val owner=pool.submit<SourceReply?> { SourceVerification.await("fixture-cancel",run()) { entered.countDown();release.await();throw CancellationException() } }
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            val follower=pool.submit<SourceReply?> { SourceVerification.await("fixture-cancel",run()) { SourceReply(base,"retried") } }
            Thread.sleep(50);release.countDown()
            assertTrue(runCatching {owner.get(2,TimeUnit.SECONDS)}.isFailure)
            assertEquals("retried",follower.get(2,TimeUnit.SECONDS)?.body)
        } finally {release.countDown();pool.shutdownNow()}
    }

    @Test fun icuDetectsRepresentativeLongLegacyAndUnicodeDocuments() {
        val samples = mapOf("Shift_JIS" to "これは自分で書いた小説の文章です。青い空と海の間をゆっくりと歩いています。",
            "Big5" to "這是一段自行編寫的繁體中文測試文章，讀者可以閱讀圖書、尋找書籤，並且儲存閱讀進度。",
            "GB18030" to "这是一段自行编写的简体中文测试文章，读者可以阅读图书、寻找书签，并且保存阅读进度。")
        for ((encoding,text) in samples) { val repeated = text.repeat(20); assertEquals(encoding,repeated,SourceResources.text(repeated.toByteArray(charset(encoding)))) }
        val text="自编 Unicode"; assertEquals(text,SourceResources.text(text.toByteArray(Charsets.UTF_8)))
        assertEquals("\uFEFF$text",SourceResources.text(byteArrayOf(-1,-2)+text.toByteArray(Charsets.UTF_16LE)))
    }

    @Test fun libraryFunctionsUseCurrentBindingsButExplicitGlobalsAreSourceScoped() {
        val library="function current(){return this.result+'|'+this.java.getTag()+'|'+this.book.name;}"
        fun engine(name: String, origin: String = base) = BookSourceEngine(mapOf("bookSourceUrl" to origin,"bookSourceName" to name,"jsLib" to library,
            "ruleContent" to mapOf("content" to "@js:globalThis.n=(globalThis.n||0)+1;current()+'|'+globalThis.n")),run())
        val one=engine("A").execute("content","$base/c",book=mapOf("name" to "甲","bookUrl" to "$base/b"))
        val two=engine("B").execute("content","$base/c",book=mapOf("name" to "乙","bookUrl" to "$base/b"))
        assertEquals("fetched|A|甲|1",one); assertEquals("fetched|B|乙|2",two)
        assertEquals("fetched|C|丙|1",engine("C","https://other.invalid").execute("content","$base/c",book=mapOf("name" to "丙")))
        SourceScriptScopes.refresh(library)
        assertEquals("fetched|A|甲|1",engine("A").execute("content","$base/c",book=mapOf("name" to "甲")))
    }

    @Test fun browserAwaitRefetchesWithUpdatedSessionOrReturnsCapturedDom() {
        val state=SourceState(); var calls=0
        val run=SourceRun(state=state,fetch={url,_,headers,_ -> calls++; assertEquals("new",headers["Authorization"]);SourceReply(url,"native")},
            web={request -> assertTrue(request.interactive); assertTrue(request.captureBody);state.put("login","header","{\"Authorization\":\"new\"}");SourceReply("$base/final","<p>DOM</p>")})
        assertEquals("native",host(run=run).script("java.startBrowserAwait('$base/login','验证').body()")); assertEquals(1,calls)
        assertEquals("$base/final|<p>DOM</p>",host(run=run).script("var r=java.startBrowserAwait('$base/login','验证',false);r.url()+'|'+r.body()"));assertEquals(1,calls)
        assertEquals("original",host(run=run).script("java.startBrowserAwait('$base/login','验证',true,'original').body()"));assertEquals(1,calls)
    }

    @Test fun asyncBrowserAndCaptchaUseHostCallbacksAndCanCancel() {
        val opened=mutableListOf<SourceWebRequest>();var image=""
        val run=SourceRun(fetch={url,_,_,_->SourceReply(url,"",data="captcha".toByteArray())},openBrowser={opened.add(it)},verifyCode={image=String(it);"1234"})
        assertEquals("1234",host(run=run).script("java.startBrowser('$base/login','验证');java.showBrowser('$base/extra','<p>fixture</p>','document.title=\"ready\"');java.getVerificationCode('$base/image')"))
        assertEquals(2,opened.size);assertEquals("验证",opened[0].title);assertEquals("document.title=\"ready\"",opened[1].script);assertEquals("captcha",image)
        assertTrue(runCatching { host(run=SourceRun(fetch={u,_,_,_->SourceReply(u,"",data=byteArrayOf(1))},verifyCode={null})).script("java.getVerificationCode('$base/image')") }.isFailure)
    }

    @Test fun verificationJoinsConcurrentRequestsAndRestoresWorkBudget() {
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val actions=AtomicInteger();val results=CopyOnWriteArrayList<SourceReply?>()
        val pool=Executors.newFixedThreadPool(2)
        try {
            val first=pool.submit { results.add(SourceVerification.await("fixture-join",run()) { actions.incrementAndGet();entered.countDown();release.await();SourceReply(base,"ok") }) }
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            val second=pool.submit { results.add(SourceVerification.await("fixture-join",run()) { actions.incrementAndGet();SourceReply(base,"wrong") }) }
            Thread.sleep(50);release.countDown();first.get(2,TimeUnit.SECONDS);second.get(2,TimeUnit.SECONDS)
            assertEquals(1,actions.get());assertEquals(1,results.count { it==null });assertEquals("ok",results.filterNotNull().single().body)
        } finally { release.countDown();pool.shutdownNow() }
        val budget=SourceRun(fetch={u,_,_,_->SourceReply(u,"")},deadline=System.nanoTime()+100_000_000)
        val before=budget.deadline;budget.awaitUser { Thread.sleep(120) };budget.check();assertTrue(budget.deadline>before+100_000_000)
    }

    @Test fun lockIsReentrantAndSingleFlightCoalescesSuccessButRetriesFailure() {
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val calls=AtomicInteger();val pool=Executors.newFixedThreadPool(2)
        val key=SourceLocks.key(base,"fixture-lock")
        try {
            val first=pool.submit { SourceLocks.execute(key,2000,true,run()) { calls.incrementAndGet();entered.countDown();release.await();SourceLocks.execute(key,0,true,run()){fail("recursive single flight")} } }
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            val second=pool.submit { SourceLocks.execute(key,2000,true,run()) { calls.incrementAndGet() } }
            Thread.sleep(50);release.countDown();first.get(2,TimeUnit.SECONDS);second.get(2,TimeUnit.SECONDS);assertEquals(1,calls.get())
        } finally { release.countDown();pool.shutdownNow() }
        assertTrue(runCatching { SourceLocks.execute(key,0,true,run()){error("failure")} }.isFailure)
        SourceLocks.execute(key,0,true,run()){calls.incrementAndGet()};assertEquals(2,calls.get())
        SourceLocks.execute(key,0,false,run()){SourceLocks.execute(key,0,false,run()){calls.incrementAndGet()}};assertEquals(3,calls.get())
        val counter=SourceLocks.key(base,"fixture-counter");assertEquals(0,SourceLocks.tick(counter));assertEquals(1,SourceLocks.tick(counter));assertEquals(0,SourceLocks.tick(SourceLocks.key("other","fixture-counter")))
    }

    @Test fun fileRenameAttributesAndBoundedArchiveBackendAreRealOperations() {
        val root=temp.newFolder(); val resources=SourceResources(root,Any()){}
        val a=resources.file("a");val b=resources.file("b");assertTrue(a.createNewFile());assertTrue(a.renameTo(b));assertFalse(a.exists());assertTrue(b.exists())
        assertTrue(b.setLastModified(1234567890000));assertEquals(1234567890000,b.lastModified());assertEquals(0,b.compareTo(resources.file("b")))
        assertTrue(runCatching { b.renameTo(SourceResources(temp.newFolder(),Any()){}.file("escape")) }.isFailure)
        val backend=SourceArchiveBackend { _,check,entry -> check();entry("book.txt",false,"自编正文".byteInputStream());Unit }
        assertEquals("自编正文",String(SourceResources.archiveEntry(byteArrayOf(1),"book.txt",backend){ }!!))
    }

    @Test fun nativeParsingAndUrlsCannotBypassControlledNetwork() {
        val e=host()
        assertEquals("undefined|/path",e.script("var u=java.connect('$base/path').raw().request().url();typeof u.openStream+'|'+u.getPath()"))
        assertTrue(runCatching { e.script("org.jsoup.Jsoup.parse('<p>x</p>').connection().url('$base').get()") }.isFailure)
        assertTrue(runCatching { e.script("java.connect('$base').raw().request().url().getContent()") }.isFailure)
        assertTrue(runCatching { e.script("java.getFile('/').getClass()") }.isFailure)
        val data=host(run=SourceRun(fetch={u,_,_,_->SourceReply(u,"ok")},appConfig=mapOf("theme" to mapOf("isNight" to true))))
        assertEquals("key|true",data.script("var m=java.getThemeConfigMap();var u=java.connect('$base/key').raw().request().url();m.put(u,'key');m.get(u)+'|'+m.keySet().contains(u)"))
        val xml = "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///fixture-must-not-be-read'>]><x>&e;</x>"
        val code = org.mewx.wenku8_flutter.legado.js.SourceGson.gson.toJson(xml)
        assertTrue(e.script("try{new XML($code);'unsafe'}catch(e){String(e)}").toString().contains("External XML declarations are disabled"))
    }

    @Test fun ruleBeanAccessorsMutateTheLiveDefinitionWithoutLosingUnknownFields() {
        val e=host(mapOf("ruleContent" to mapOf("content" to "old", "customOption" to "kept")))
        assertEquals("new|kept|li|@js:function login(){}",e.script("""
            source.getContentRule().setContent('new');source.getTocRule().chapterList='li';source.setLoginUrl('@js:function login(){}');
            source.getRuleContent().getContent()+'|'+source.ruleContent.customOption+'|'+source.getTocRule().getChapterList()+'|'+source.getLoginUrl()
        """))
    }

    @Test fun preUpdateCanRefreshTocUrlAndKeepsTheNewAddressAcrossOperations() {
        val fetched=mutableListOf<String>();val state=SourceState()
        val source=mapOf("ruleToc" to mapOf("preUpdateJs" to "java.refreshTocUrl()","chapterList" to "li","chapterName" to "a@text","chapterUrl" to "a@href"),
            "ruleBookInfo" to mapOf("tocUrl" to "#toc@href"))
        fun e()=host(source,SourceRun(state=state,fetch={u,_,_,_->fetched.add(u);SourceReply(u,if(u.endsWith("/b")) "<a id='toc' href='/new-toc'>目录</a>" else "<li><a href='/c'>第一章</a></li>")}))
        val book=mapOf("bookUrl" to "$base/b","tocUrl" to "$base/old-toc","name" to "自编书")
        val rows=e().execute("toc","$base/old-toc",book=book) as List<*>
        assertEquals("第一章",(rows.single() as Map<*, *>)["title"])
        assertEquals(listOf("$base/b","$base/new-toc"),fetched)
        assertTrue(state.get("book-resolution","$base/b").contains("new-toc"))
        assertTrue(runCatching { e().script("java.refreshTocUrl()") }.isFailure)
    }
    @Test fun sourceCleanupRestoresOwnPermissionFlagsWithoutFollowingLinks() {
        val root=temp.newFolder();val dir=java.io.File(root,"nested").apply{mkdir()};java.io.File(dir,"data").writeText("fixture")
        val outside=temp.newFile().apply{writeText("keep")}
        java.nio.file.Files.createSymbolicLink(java.io.File(root,"link").toPath(),outside.toPath())
        dir.setWritable(false,true)
        assertTrue(SourceResources.clear(root));assertFalse(root.exists());assertEquals("keep",outside.readText())
    }
    @Test fun revokedStateCannotRecreateLargeFilesAfterSessionRemoval() {
        val root=temp.newFolder();var active=true
        val state=SourceState(SourceBigVariables(root,{it},{it})){check(active)}
        state.putRuleVariable("book:fixture","large","x".repeat(10000))
        synchronized(state.fileLock){active=false;assertTrue(SourceResources.clear(root))}
        assertTrue(runCatching{state.putBig("book:fixture","large","new")}.isFailure)
        assertTrue(runCatching{state.putRuleVariable("book:fixture","large","y".repeat(10000))}.isFailure)
        assertFalse(root.exists())
    }
}
