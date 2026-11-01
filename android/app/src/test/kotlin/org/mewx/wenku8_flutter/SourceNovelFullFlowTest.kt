package org.mewx.wenku8_flutter

import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.URI
import java.net.Socket
import java.io.ByteArrayInputStream
import org.junit.Assert.*
import org.junit.Test

/** A real local HTTP server, self-authored pages and one generic novel rule. */
class SourceNovelFullFlowTest {
    @Test fun loginSearchDetailPagedVolumesContentAndImageShareOneIsolatedSession() {
        val server=FixtureHttpServer()
        val calls=java.util.concurrent.CopyOnWriteArrayList<String>()
        server.createContext("/") { exchange ->
            val path=exchange.requestURI.path;calls.add(path)
            val signed=exchange.requestHeaders.getFirst("Cookie").orEmpty().contains("fixture_session=ready")
            var status=200
            val body=when {
                path=="/login" -> { assertEquals("POST",exchange.requestMethod);exchange.requestBody.readBytes();exchange.responseHeaders.add("Set-Cookie","fixture_session=ready; Path=/; HttpOnly");"ok" }
                !signed -> {status=401;"sign in"}
                path=="/search" -> "<li class='book'><a href='/book'>星海档案</a><b>自编作者</b></li>"
                path=="/book" -> "<h1>星海档案</h1><div id='intro'>自编简介</div><span id='kind'>奇幻,冒险</span><a id='toc' href='/toc'>目录</a><img id='cover' src='/cover.png'>"
                path=="/toc" -> "<ul><li data-volume='true'><a>第一卷</a></li><li><a href='/c1'>第一章</a></li></ul><a class='next' href='/toc2'>下一页</a>"
                path=="/toc2" -> "<ul><li data-volume='true'><a>第二卷</a></li><li><a href='/c2'>第二章</a></li></ul>"
                path=="/c1" && exchange.requestURI.query==null -> "<article><p>第一段</p><img src='/figure.png'></article><a class='next' href='/c1?p=2'>继续</a>"
                path=="/c1" -> "<article><p>第二段</p></article><a class='next' href='/c2'>下一章</a>"
                path.endsWith(".png") -> "fixture-image-bytes"
                else -> {status=404;"missing"}
            }.toByteArray(Charsets.UTF_8)
            exchange.responseHeaders.add("Content-Type",if(path.endsWith(".png")) "application/octet-stream" else "text/html; charset=UTF-8")
            exchange.sendResponseHeaders(status,body.size.toLong());exchange.responseBody.use{it.write(body)};exchange.close()
        }
        server.start()
        try {
            val base="http://127.0.0.1:${server.address.port}"; val state=SourceState();val network=SourceNetwork()
            val source=mapOf("bookSourceUrl" to base,"bookSourceName" to "自编完整流程",
                "loginUi" to "[{\"name\":\"账号\",\"type\":\"text\"}]",
                "loginUrl" to "@js:function login(){java.post('$base/login','fixture=one',null)}",
                "searchUrl" to "/search?q={{key}}&p={{page}}",
                "ruleSearch" to mapOf("bookList" to "li.book","name" to "a@text","bookUrl" to "a@href","author" to "b@text"),
                "ruleBookInfo" to mapOf("name" to "h1@text","intro" to "#intro@text","kind" to "#kind@text","tocUrl" to "#toc@href","coverUrl" to "#cover@src"),
                "ruleToc" to mapOf("chapterList" to "li","chapterName" to "a@text","chapterUrl" to "a@href","isVolume" to "@data-volume","nextTocUrl" to "a.next@href"),
                "ruleContent" to mapOf("content" to "article@html","nextContentUrl" to "a.next@href"))
            fun engine():BookSourceEngine {
                lateinit var run:SourceRun
                run=SourceRun(state=state,fetch={u,m,h,b->network.text(base,u,m,h,b,run)},
                    fetchOptions={u,m,h,b,o->network.text(base,u,m,h,b,run,o)},
                    fetchBytes={u,m,h,b,o->network.bytes(base,u,m,h,b,run,o).let{SourceReply(it.url,"",it.status,it.headers,it.data)}})
                return BookSourceEngine(source,run)
            }
            engine().execute("login",book=mapOf("loginInfo" to mapOf("账号" to "self-authored")))
            assertTrue(network.cookie(base,base).contains("fixture_session=ready"));assertEquals("",network.cookie("other",base))
            val found=engine().execute("search",key="星海") as Map<*, *>
            @Suppress("UNCHECKED_CAST") val selected=(found["items"] as List<*>).single() as Map<String,Any?>
            assertEquals("星海档案",selected["name"])
            @Suppress("UNCHECKED_CAST") val detail=engine().execute("detail","$base/book",book=selected) as Map<String,Any?>
            assertEquals("自编简介",detail["intro"]);assertTrue(detail["kind"].toString().contains("冒险"))
            @Suppress("UNCHECKED_CAST") val toc=engine().execute("toc",detail["tocUrl"].toString(),book=detail) as List<Map<String,Any?>>
            assertEquals(listOf("第一卷","第一章","第二卷","第二章"),toc.map{it["title"]})
            assertEquals(2,toc.count{it["isVolume"]==false})
            val text=engine().execute("content","$base/c1",book=detail,chapter=toc[1]+("nextChapterUrl" to "$base/c2")).toString()
            assertTrue(text.contains("第一段"));assertTrue(text.contains("第二段"));assertTrue(text.contains("<!--image-->$base/figure.png<!--image-->"))
            assertFalse(calls.contains("/c2"))
            assertEquals("fixture-image-bytes",String(engine().image("$base/figure.png",false,book=detail)))
        } finally {server.stop(0)}
    }
}

private class FixtureHeaders {
    val values=linkedMapOf<String,MutableList<String>>()
    fun add(key:String,value:String) {values.getOrPut(key){mutableListOf()}.add(value)}
    fun getFirst(key:String)=values.entries.firstOrNull{it.key.equals(key,true)}?.value?.firstOrNull()
}
private class FixtureExchange(private val socket:Socket) {
    val requestMethod:String
    val requestURI:URI
    val requestHeaders=FixtureHeaders()
    val responseHeaders=FixtureHeaders()
    val requestBody:ByteArrayInputStream
    val responseBody get()=socket.getOutputStream()
    init {
        socket.soTimeout=3000
        val reader=socket.getInputStream().bufferedReader(Charsets.UTF_8)
        val first=reader.readLine().split(' ');requestMethod=first[0];requestURI=URI(first[1])
        while(true) {val line=reader.readLine()?:error("Incomplete fixture request");if(line.isEmpty())break
            requestHeaders.add(line.substringBefore(':'),line.substringAfter(':').trim())}
        val size=requestHeaders.getFirst("Content-Length")?.toInt()?:0
        require(size in 0..32768);val data=CharArray(size);var read=0
        while(read<size){val count=reader.read(data,read,size-read);check(count>0);read+=count}
        requestBody=ByteArrayInputStream(String(data).toByteArray())
    }
    fun sendResponseHeaders(code:Int,size:Long) {
        val headers=responseHeaders.values.entries.flatMap{(key,values)->values.map{"$key: $it\r\n"}}.joinToString("")
        responseBody.write("HTTP/1.1 $code Fixture\r\nContent-Length: $size\r\nConnection: close\r\n$headers\r\n".toByteArray())
    }
    fun close()=socket.close()
}
private class FixtureHttpServer {
    private val server=ServerSocket().apply{bind(InetSocketAddress("127.0.0.1",0));soTimeout=10000}
    val address get()=server.localSocketAddress as InetSocketAddress
    private lateinit var handler:(FixtureExchange)->Unit
    private var worker:Thread?=null
    fun createContext(path:String,action:(FixtureExchange)->Unit){require(path=="/");handler=action}
    fun start(){worker=kotlin.concurrent.thread(isDaemon=true,name="novel-fixture-http"){
        while(!server.isClosed) try {server.accept().use{handler(FixtureExchange(it))}} catch(error:java.net.SocketException){if(!server.isClosed)throw error}
    }}
    fun stop(@Suppress("UNUSED_PARAMETER") delay:Int){server.close();worker?.join(1000)}
}
