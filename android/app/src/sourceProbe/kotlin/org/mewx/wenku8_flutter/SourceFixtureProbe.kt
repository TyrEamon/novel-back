package org.mewx.wenku8_flutter

import android.content.Context
import androidx.annotation.Keep
import com.google.gson.Gson
import java.io.File

/** Opt-in device verification; all rules and documents are self-authored and offline. */
@Keep
object SourceFixtureProbe {
    /** Independent emulator only: own HTML, real renderer and native sheet. */
    @JvmStatic fun completion(context: Context): String {
        val report=mutableListOf<Map<String,Any?>>()
        var stage="native-hidden-dom"
        try {
            check(context.packageName.endsWith(".source_preview"))
            val key="self-authored-completion"
            fun run()=SourceRun(fetch={_,_,_,_->error("No external network in browser fixture")},deadline=System.nanoTime()+60_000_000_000L)
            val renderer=SourceWebRuntime(context)
            val hidden=renderer.render(key,SourceWebRequest("http://127.0.0.1/fixture",
                html="<html><body><p id='value'>自编网页正文</p></body></html>",script="document.getElementById('value').textContent"),run())
            check(hidden.body=="自编网页正文")
            report.add(mapOf("check" to stage,"status" to "passed"))
            stage="native-browser-sheet-config-dom"
            val browser=renderer.render(key,SourceWebRequest("http://127.0.0.1/fixture",interactive=true,captureBody=true,browserSheet=true,
                title="自编浏览器测试",browserConfig="{\"heightPercentage\":0.65,\"isDraggable\":false,\"webViewInitialScale\":100}",
                html="""<html><body><p id='value'>自编交互网页正文</p><script>document.cookie='fixture_completion=yes;path=/';</script></body></html>""",
                script="setTimeout(function(){java.upConfig('{\"heightPercentage\":0.55}');java.dismiss()},1400)"),run())
            check(browser.body.contains("自编交互网页正文"))
            report.add(mapOf("check" to stage,"status" to "passed"))
        } catch(failure:Throwable) { report.add(mapOf("check" to stage,"status" to "failed","failure" to failure.javaClass.simpleName,"offlineTrace" to failure.stackTraceToString().take(3500))) }
        return Gson().toJson(report)
    }
    /** Headless shrinker/runtime check: no discovery search, UI, network,
     * installed source rules or account/session storage is accessed. */
    @JvmStatic fun runtimeOnly(context: Context): String {
        val report = mutableListOf<Map<String, Any?>>()
        var stage = "package-guard"
        try {
            check(context.packageName.endsWith(".source_preview"))
            fun runner(source: Map<String, Any?> = emptyMap(), state: SourceState = SourceState()) =
                BookSourceEngine(mapOf("bookSourceUrl" to "https://fixture.invalid", "bookSourceName" to "自编验证") + source,
                    SourceRun(state = state, fetch = { _, _, _, _ -> error("Offline runtime fixture must not fetch") }))
            stage = "pinned-js-runtime"
            val engine = runner()
            check(engine.evaluate("@js:var a={b:'正文'};a?.b??'无'", "") == "正文")
            check(engine.evaluate("@js:var x=<r><p>正文</p></r>;x.p.toString()", "") == "正文")
            check(engine.evaluate("@js:try{new XML(\"<!DOCTYPE x><x/>\");'unsafe'}catch(e){String(e).indexOf('External XML declarations are disabled')>=0}", "") == "true")
            check(engine.evaluate("@js:if(true){let a='旧规则';} a", "") == "旧规则")
            check(engine.evaluate("@js:CryptoJS.MD5('hello').toString()", "") == "5d41402abc4b2a76b9719d911017c592")
            check(engine.evaluate("@js:typeof Packages", "") == "undefined")
            report.add(mapOf("check" to stage, "status" to "passed"))
            stage = "native-rar4-rar5-7z"
            val archives = listOf("rar4.rar" to "test.txt", "rar5.rar" to "helloworld.txt", "fixture.7z" to "fixture.txt")
            for ((name, path) in archives) {
                val bytes = context.assets.open("source-fixtures/$name").use { it.readBytes() }
                val extracted = org.mewx.wenku8_flutter.legado.SourceResources.archiveEntry(bytes, path, SourceNativeArchive) {}
                check(extracted != null && extracted.isNotEmpty()) { "Native archive fixture $name" }
                if (name.endsWith("7z")) check(String(extracted).contains("自编压缩测试正文"))
            }
            report.add(mapOf("check" to stage, "status" to "passed"))
            stage = "native-fluent-rules-and-safe-url"
            val apiHost=BookSourceEngine(mapOf("bookSourceUrl" to "https://fixture.invalid"),SourceRun(
                fetch={u,_,_,_->SourceReply(u,"fixture")},appConfig=mapOf("theme" to mapOf("isNight" to true))))
            check(apiHost.evaluate("""@js:
                java.setContent('<a>甲</a><a>乙</a>');var rules=java.splitSourceRule('a@text');rules.get(0).toString();
                var u=java.connect('https://fixture.invalid/url').raw().request().url();var m=java.getThemeConfigMap();m.put(u,'safe');
                java.getStringList(rules).toArray().join(',')+'|'+m.get(u)+'|'+u.getPath()
            """, "") == "甲,乙|safe|/url")
            report.add(mapOf("check" to stage, "status" to "passed"))
            stage = "native-charset-language-shared-library"
            val library = "function fixture(){return this.result+':'+this.java.t2s('圖書');}"
            val first = runner(mapOf("jsLib" to library))
            check(first.evaluate("@js:globalThis.count=(globalThis.count||0)+1;fixture()+':'+globalThis.count", "body") == "body:图书:1")
            check(runner(mapOf("jsLib" to library)).evaluate("@js:fixture()+':'+globalThis.count", "next") == "next:图书:1")
            check(runner(mapOf("jsLib" to library)).evaluate("@js:var xml=<r><p>共享XML</p></r>;xml.p.toString()", "") == "共享XML")
            val charsetText="這是自行編寫的繁體測試文章，圖書、章節與書籤都應保留。".repeat(20)
            check(org.mewx.wenku8_flutter.legado.SourceResources.text(charsetText.toByteArray(charset("Big5"))) == charsetText)
            SourceScriptScopes.refresh(library)
            report.add(mapOf("check" to stage, "status" to "passed"))
            stage = "js-source-marshaller"
            val script = """function getBookInfo(book){return {name:'自编作品',intro:'自编简介'};}
                function getChapters(book){return [{title:'第一卷',url:'第一卷',isVolume:true},{title:'正文',url:'/chapter'}];}
                function getContent(chapter,book,nextChapterUrl){return '自编正文';}"""
            val book = mapOf("name" to "原名称", "bookUrl" to "https://fixture.invalid/book", "tocUrl" to "https://fixture.invalid/toc")
            val details = runner(mapOf("mainJs" to script)).execute("detail", "https://fixture.invalid/book", book = book) as Map<*, *>
            check(details["name"] == "自编作品" && details["intro"] == "自编简介")
            val chapters = runner(mapOf("mainJs" to script)).execute("toc", "https://fixture.invalid/toc", book = book) as List<*>
            check(chapters.size == 2 && (chapters[0] as Map<*, *>)["isVolume"] == true)
            check((chapters[1] as Map<*, *>)["url"] == "https://fixture.invalid/chapter")
            report.add(mapOf("check" to stage, "status" to "passed"))
            stage = "login-v2-protocol"
            val state = SourceState()
            val login = mapOf("loginUi" to "{\"version\":2}", "loginUrl" to """@js:
                function loginUi(state){return {rows:[{name:'自编字段',key:'sample',type:'text'},{name:'完成',type:'button',action:'done'}]};}
                function loginAction(action,state,form){return {state:{stage:'done'},login:{fixture:'saved'},close:true};}""")
            val ui = runner(login, state).execute("loginUi") as Map<*, *>
            check((ui["rows"] as List<*>).size == 2)
            val done = runner(login, state).execute("login", key = "done", book = mapOf("loginInfo" to mapOf("sample" to "fixture"))) as Map<*, *>
            check(done["close"] == true && state.get("login", "info").contains("saved"))
            report.add(mapOf("check" to stage, "status" to "passed"))
        } catch (failure: Throwable) {
            report.add(mapOf("check" to stage, "status" to "failed", "failure" to failure.javaClass.simpleName,
                "offlineTrace" to failure.stackTraceToString().take(3500)))
        }
        return Gson().toJson(report)
    }

    @JvmStatic fun run(context: Context, interactive: Boolean, loginOnly: Boolean = false): String {
        val report = mutableListOf<Map<String, Any?>>()
        var stage = "package-guard"
        try {
            check(context.packageName.endsWith(".source_preview"))
            if (!loginOnly) {
            stage = "script-json"
            val scriptEngine = BookSourceEngine(mapOf("bookSourceUrl" to "https://source-fixture.invalid"),
                SourceRun(fetch = { _, _, _, _ -> error("Offline script fixture must not request a page") }))
            check(scriptEngine.evaluate("@js:JSON.stringify(java.getElements('p'))", "<p>甲</p>") == "[\"<p>甲</p>\"]")
            stage = "script-mutable-list"
            check(scriptEngine.evaluate("@js:var rows=java.getElements('p'); rows[0]='乙'; rows.size() + ':' + rows[0]", "<p>甲</p>") == "1:乙")
            stage = "script-jsoup"
            check(scriptEngine.evaluate("@js:org.jsoup.Jsoup.parse(result).select('p').text()", "<p>正文</p>") == "正文")
            stage = "script-crypto"
            check(scriptEngine.evaluate("@js:var c=java.createSymmetricCrypto('AES/ECB/PKCS5Padding','1234567890123456'); c.decryptStr(c.encryptBase64('测试'))", "") == "测试")
            report.add(mapOf("check" to "android-script-host", "status" to "passed"))
            stage = "script-request-and-jsonpath"
            val requestEngine = BookSourceEngine(mapOf("bookSourceUrl" to "https://source-fixture.invalid",
                "header" to "{\"X-Page\":\"{{page}}\"}", "searchUrl" to "/search?q={{key}}",
                "ruleSearch" to mapOf("bookList" to "$.items", "name" to "$.name", "bookUrl" to "$.url")),
                SourceRun(fetch = { url, method, headers, _ ->
                    check(url.contains("q=%E6%98%9F%E6%B5%B7")); check(method == "GET"); check(headers["X-Page"] == "1")
                    SourceReply(url, "{\"items\":[{\"name\":\"星海\",\"url\":\"/book\"}]}") }))
            val parsed = requestEngine.execute("search", key = "星海") as Map<*, *>
            check(((parsed["items"] as List<*>).single() as Map<*, *>)["name"] == "星海")
            report.add(mapOf("check" to stage, "status" to "passed"))
            }

            fun clearProfile(key: String) = SourceWebRuntime(context).render(key,
                SourceWebRequest("https://source-fixture.invalid/", clearProfile = true),
                SourceRun(fetch = { _, _, _, _ -> error("Offline profile clear must not fetch") }))
            if (interactive) {
                stage = "interactive-web-login"
                val key = "fixture-interactive-login"
                clearProfile(key)
                val receivedCookies = mutableListOf<String>()
                val sessionNetwork = SourceNetwork()
                val loginRun = SourceRun(fetch = { _, _, _, _ -> error("Offline login fixture must not fetch") },
                    deadline = System.nanoTime() + 10 * 60_000_000_000L,
                    cookieWrite = { address, value -> receivedCookies.add(value); sessionNetwork.setCookie(key, address, value) })
                SourceWebRuntime(context).render(key, SourceWebRequest("http://127.0.0.1/login",
                    html = """<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="padding:28px;font:16px sans-serif;background:#f7f6f2;color:#313437"><h2>书源网页登录验证</h2><p>本机自编测试页面，无需填写账号或密码。使用系统返回，或点击右上角「保存并返回」。</p><script>document.cookie='fixture_login=one;path=/';localStorage.setItem('fixture-login','ready');history.pushState({},'', '/fixture-signed-in');</script></body></html>""",
                    interactive = true), loginRun)
                stage = "interactive-web-login-cookies"
                check(receivedCookies.any { it.contains("fixture_login=one") })
                stage = "web-login-cookie-autosave-off-request"
                java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1")).use { server ->
                    val reached = java.util.concurrent.atomic.AtomicBoolean()
                    val hasCookie = java.util.concurrent.atomic.AtomicBoolean()
                    val hasPair = java.util.concurrent.atomic.AtomicBoolean()
                    val responder = kotlin.concurrent.thread(isDaemon = true) {
                        try {
                        server.accept().use { client ->
                            reached.set(true)
                            val input = client.getInputStream().bufferedReader()
                            input.readLine()
                            var authenticated = false
                            while (true) {
                                val line = input.readLine() ?: break
                                if (line.isEmpty()) break
                                if (line.startsWith("Cookie:", true)) {
                                    hasCookie.set(true); hasPair.set(line.contains("fixture_login"))
                                    if (line.contains("fixture_login=one")) authenticated = true
                                }
                            }
                            val body = if (authenticated) "fixture-session-accepted" else "fixture-session-missing"
                            val bytes = body.toByteArray()
                            client.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray())
                            client.getOutputStream().write(bytes); client.getOutputStream().flush()
                        }
                        } catch (failure: java.net.SocketException) {
                            // A failed fixture closes its own listening socket.
                            if (!server.isClosed) throw failure
                        }
                    }
                    val address = "http://127.0.0.1:${server.localPort}/private"
                    val seeded = sessionNetwork.cookie(key, address).contains("fixture_login=one")
                    val reply = sessionNetwork.text(key, address, "GET", emptyMap(), null,
                        SourceRun(fetch = { _, _, _, _ -> error("No nested fixture requests") }),
                        SourceHttpOptions(cookieJar = false))
                    check(reply.body == "fixture-session-accepted") {
                        "Offline login HTTP fixture: seeded=$seeded reached=${reached.get()} cookieHeader=${hasCookie.get()} namedPair=${hasPair.get()} status=${reply.status} bodyKind=${if (reply.body == "fixture-session-missing") "missing" else "other"} bodyLength=${reply.body.length}"
                    }
                    responder.join(1000)
                }
                report.add(mapOf("check" to stage, "status" to "passed"))
                fun checkProfile() = SourceWebRuntime(context).render(key,
                    SourceWebRequest("http://127.0.0.1/login", html = "<html><body>profile</body></html>",
                        script = "document.cookie+'|'+(localStorage.getItem('fixture-login')||'')"),
                    SourceRun(fetch = { _, _, _, _ -> error("Offline profile fixture must not fetch") })).body
                stage = "interactive-web-login-profile-retention"
                val retained = checkProfile()
                check(retained == "fixture_login=one|ready") { "Offline fixture retained: $retained" }
                stage = "interactive-web-login-profile-clear"
                clearProfile(key)
                check(checkProfile() == "|")
                report.add(mapOf("check" to "interactive-web-login", "status" to "passed", "profileCleared" to true))
            }

            if (!loginOnly) {
            stage = "isolated-web-renderer"
            clearProfile("fixture-A"); clearProfile("fixture-B")
            fun web(key: String, cookie: String) = SourceWebRuntime(context).render(key,
                SourceWebRequest("https://source-fixture.invalid/", html = "<html><body><p id='text'>正文</p></body></html>",
                    script = "if(document.cookie.indexOf('fixture=one')>=0)localStorage.setItem('fixture','A'); document.querySelector('#text').textContent + '|' + document.cookie.split(';').map(function(x){return x.trim()}).filter(Boolean).sort().join(';') + '|' + (localStorage.getItem('fixture')||'')"),
                SourceRun(fetch = { _, _, _, _ -> error("Offline web fixture must not request a page") }, cookieRead = { cookie })).body
            check(web("fixture-A", "fixture=one; other=two") == "正文|fixture=one;other=two|A")
            check(web("fixture-B", "") == "正文||")
            check(web("fixture-A", "") == "正文|fixture=one;other=two|A")
            clearProfile("fixture-B")
            check(web("fixture-A", "") == "正文|fixture=one;other=two|A")
            clearProfile("fixture-A")
            check(web("fixture-A", "") == "正文||")
            report.add(mapOf("check" to stage, "status" to "passed"))

            stage = "generic-reading-chain"
            val base = "https://source-fixture.invalid"
            val dataImage = "data:image/png;base64,AQIDBA=="
            val pages = mapOf(
                "/search" to "<ul class='books'><li><a href='/book'>纸间示例</a><b class='author'>自编作者</b></li></ul>",
                "/book" to "<h1>纸间示例</h1><a rel='author' href='/authors/demo'>自编作者</a><div class='tags'><a href='/tags/demo'>示例</a></div><div class='synopsis'>自行编写的功能验证文本。</div><a class='directory' href='/toc'>目录</a>",
                "/toc" to "<ul class='toc'><li data-volume='true'>第一卷</li><li><a href='/c1'>第一章</a></li><li><a href='/c2'>第二章</a></li></ul>",
                "/c1" to "<div id='content'><p>第一段是自行编写的测试文字。</p><img src='$dataImage'><p>第二段用于验证插图顺序。</p></div>",
            )
            val source = mapOf("bookSourceUrl" to base, "searchUrl" to "/search?q={{key}}",
                "ruleSearch" to mapOf("bookList" to ".books li", "name" to "a@text", "bookUrl" to "a@href", "author" to ".author@text"),
                "ruleBookInfo" to mapOf("name" to "h1@text", "author" to "[rel=author]@text", "kind" to ".tags a@text", "intro" to ".synopsis@text", "tocUrl" to ".directory@href"),
                "ruleToc" to mapOf("chapterList" to ".toc li", "chapterName" to "@text", "chapterUrl" to "a@href", "isVolume" to "@data-volume"),
                "ruleContent" to mapOf("content" to "#content@html"))
            val engine = BookSourceEngine(source, SourceRun(fetch = { url, _, _, _ ->
                SourceReply(url, pages[java.net.URI(url).path] ?: error("Unknown offline fixture")) }))
            val search = engine.execute("search", key = "纸间") as Map<*, *>
            @Suppress("UNCHECKED_CAST")
            val book = (search["items"] as List<*>).single() as Map<String, Any?>
            check(book["name"] == "纸间示例")
            @Suppress("UNCHECKED_CAST")
            val detail = engine.execute("detail", "$base/book", book = book) as Map<String, Any?>
            check(detail["intro"] == "自行编写的功能验证文本。")
            check(detail["authorUrl"] == "$base/authors/demo")
            val full = book + detail
            val chapters = engine.execute("toc", full["tocUrl"].toString(), book = full) as List<*>
            check(chapters.size == 3 && (chapters.first() as Map<*, *>)["isVolume"] == true)
            check(chapters.drop(1).all { (it as Map<*, *>)["isVolume"] == false })
            val body = engine.execute("content", "$base/c1", book = full, chapter = mapOf("title" to "第一章", "url" to "$base/c1")) as String
            check(body.indexOf("第一段") < body.indexOf("<!--image-->"))
            check(body.indexOf("第二段") > body.indexOf("<!--image-->"))
            check(engine.image(dataImage, false, "$base/c1", full).contentEquals(byteArrayOf(1, 2, 3, 4)))
            report.add(mapOf("check" to stage, "status" to "passed", "coverage" to "offline-self-authored-rules-and-documents"))
            }
        } catch (failure: Throwable) {
            report.add(mapOf("check" to stage, "status" to "failed", "failure" to failure.javaClass.simpleName,
                "offlineTrace" to failure.stackTraceToString().take(3500)))
        }
        val json = Gson().toJson(report)
        File(context.filesDir, "source-probe-report.json").writeText(json)
        return json
    }
}
