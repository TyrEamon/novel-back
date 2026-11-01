package org.mewx.wenku8_flutter

import java.net.ServerSocket
import org.junit.Test
import org.junit.Assert.*

class SourceNetworkTest {
    private fun run() = SourceRun(fetch = { _, _, _, _ -> error("No nested requests") })
    private class FixtureServer(val handler: (String, Map<String,String>) -> Triple<Int,Map<String,String>,String>) : AutoCloseable {
        private val socket = ServerSocket(0, 10, java.net.InetAddress.getByName("127.0.0.1"))
        val origin = "http://127.0.0.1:${socket.localPort}"
        private val thread = kotlin.concurrent.thread(isDaemon = true) {
            while (!socket.isClosed) {
                try { socket.accept().use { client ->
                    val reader = client.getInputStream().bufferedReader()
                    val path = reader.readLine().split(' ')[1]
                    val headers = mutableMapOf<String,String>()
                    while (true) { val line = reader.readLine() ?: break; if (line.isEmpty()) break
                        val i = line.indexOf(':'); if (i > 0) headers[line.substring(0,i).lowercase()] = line.substring(i+1).trim() }
                    val (status, response, text) = handler(path, headers)
                    val bytes = text.toByteArray(Charsets.UTF_8)
                    val head = "HTTP/1.1 $status Reply\r\nConnection: close\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Length: ${bytes.size}\r\n" +
                        response.entries.joinToString("") { "${it.key}: ${it.value}\r\n" } + "\r\n"
                    client.getOutputStream().write(head.toByteArray()); client.getOutputStream().write(bytes); client.getOutputStream().flush()
                } } catch (failure: Exception) { if (!socket.isClosed) throw failure }
            }
        }
        override fun close() { socket.close(); thread.join(1000) }
    }
    @Test fun cookiesAreScopedAndRedirectCredentialsAreNotForwarded() {
        var leaked: String? = "not-called"
        val other = FixtureServer { _, headers ->
            leaked = headers["authorization"]
            Triple(200,emptyMap(),"ok")
        }
        val server = FixtureServer { path, headers ->
            when(path) {
                "/cookie" -> Triple(200,mapOf("Set-Cookie" to "session=fixture; Path=/; Max-Age=3600"),"ok")
                "/read" -> Triple(200,emptyMap(),headers["cookie"] ?: "none")
                "/redirect" -> Triple(302,mapOf("Location" to "${other.origin}/target"),"")
                else -> Triple(404,emptyMap(),"missing")
            }
        }
        try {
            val root = server.origin
            val network = SourceNetwork()
            network.text("first","$root/cookie","GET",emptyMap(),null,run())
            assertTrue(network.text("first","$root/read","GET",emptyMap(),null,run()).body.contains("session="))
            assertEquals("none",network.text("second","$root/read","GET",emptyMap(),null,run()).body)
            val saved = network.session("first"); val restored = SourceNetwork(); restored.restore("first",saved)
            assertTrue(restored.text("first","$root/read","GET",emptyMap(),null,run()).body.contains("session="))
            network.text("first","$root/redirect","GET",mapOf("Authorization" to "fixture-secret"),null,run())
            assertNull(leaked)
        } finally { server.close(); other.close() }
    }
    @Test fun rejectsFileAndCredentialUrls() {
        assertTrue(runCatching { SourceNetwork.url("file:///etc/passwd") }.isFailure)
        assertTrue(runCatching { SourceNetwork.url("https://user:secret@fixture.invalid") }.isFailure)
    }
    @Test fun invalidHeadersAreActionableWithoutEchoingCredentials() {
        val network = SourceNetwork()
        for ((name, value) in listOf("Authorization" to "Bearer 私密", "X-Bad\r\nInjected" to "secret", "Cookie" to "private=one\u0000")) {
            val failure = runCatching { network.text("bad", "http://127.0.0.1:1/", "GET", mapOf(name to value), null, run()) }.exceptionOrNull()
            assertTrue(failure is SourceHeaderFailure)
            assertEquals("书源请求头格式无效，请检查书源请求头或重新登录", sourceRuleFailureMessage(failure as Exception))
            assertFalse(failure.toString().contains(value))
        }
        FixtureServer { _, headers -> Triple(200, emptyMap(), headers["authorization"].orEmpty()) }.use { server ->
            assertEquals("Bearer valid", network.text("good", server.origin, "GET", mapOf("Authorization" to "Bearer valid"), null, run()).body)
        }
    }
    @Test fun accountSessionEvidenceIsScopedAndExpires() {
        val changes = mutableListOf<String>()
        val network = SourceNetwork { changes.add(it) }
        network.setCookie("one", "https://fixture.invalid", "session=fixture")
        assertTrue(network.hasCookies("one")); assertFalse(network.hasCookies("two"))
        network.removeCookie("one", "https://fixture.invalid")
        assertFalse(network.hasCookies("one")); assertEquals(listOf("one", "one"), changes)
    }
    @Test fun manualLoginCookiesAreSentWithAutomaticSavingDisabledAndSurviveRestart() {
        FixtureServer { _, headers ->
            Triple(200, mapOf("Set-Cookie" to "automatic=ignored; Path=/; Max-Age=3600"), headers["cookie"] ?: "none")
        }.use { server ->
            val network = SourceNetwork()
            val options = SourceHttpOptions(cookieJar = false)
            network.setCookie("login", server.origin, "session=fixture; preference=one")
            fun read(client: SourceNetwork, key: String = "login") = client.text(key,
                "${server.origin}/private", "GET", emptyMap(), null, run(), options).body
            val first = read(network)
            assertTrue(first.contains("session=fixture"))
            assertTrue(first.contains("preference=one"))
            assertFalse(first.contains("\$Version"))
            assertFalse(first.contains("automatic="))
            assertEquals(first, read(network))
            val restored = SourceNetwork().apply { restore("login", network.session("login")) }
            assertEquals(first, read(restored))
            assertEquals("none", read(restored, "unrelated-source"))
        }
    }
    @Test fun callTimeoutIsEnforcedAndZeroUsesTheParentBudget() {
        FixtureServer { _, _ -> Thread.sleep(150); Triple(200, emptyMap(), "slow") }.use { server ->
            val failure = runCatching { SourceNetwork().text("timeout", server.origin, "GET", emptyMap(), null, run(),
                SourceHttpOptions(callTimeout = 40)) }.exceptionOrNull()
            assertNotNull(failure)
            assertTrue(failure is java.io.InterruptedIOException || failure is java.net.SocketTimeoutException)
        }
        FixtureServer { _, _ -> Thread.sleep(60); Triple(200, emptyMap(), "zero") }.use { server ->
            assertEquals("zero", SourceNetwork().text("timeout", server.origin, "GET", emptyMap(), null, run(),
                SourceHttpOptions(callTimeout = 0)).body)
        }
    }
    @Test fun redirectsShareOneCallDeadline() {
        FixtureServer { path, _ ->
            Thread.sleep(90)
            if (path == "/start") Triple(302, mapOf("Location" to "/finish"), "") else Triple(200, emptyMap(), "too late")
        }.use { server ->
            assertTrue(runCatching { SourceNetwork().text("timeout", "${server.origin}/start", "GET", emptyMap(), null, run(),
                SourceHttpOptions(callTimeout = 140)) }.isFailure)
        }
    }
}
