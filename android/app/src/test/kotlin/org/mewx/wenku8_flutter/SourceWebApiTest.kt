package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceWebApiTest {
    private val base = "https://fixture.invalid"
    private fun BookSourceEngine.script(code: String) = evaluate("@js:$code", "fixture")

    @Test fun webHelpersCarryCacheDelayHeadersAndCaptureOptions() {
        val requests = mutableListOf<SourceWebRequest>()
        val host = BookSourceEngine(mapOf("bookSourceUrl" to base, "header" to "{\"X-Fixture\":\"web\"}"),
            SourceRun(fetch = { _, _, _, _ -> error("No HTTP refetch of captured resources") },
                web = { request -> requests.add(request); SourceReply(request.url, "$base/captured") },
                webUserAgent = { "system-webview-fixture" }))
        assertEquals("system-webview-fixture", host.script("java.getWebViewUA()"))
        assertEquals("$base/captured", host.script("java.webView('<p>fixture</p>','$base/page','document.title',true)"))
        assertTrue(requests[0].cacheFirst); assertEquals("web", requests[0].headers["X-Fixture"])
        host.script("java.webViewGetSource(null,'$base/page','trigger()', 'https://fixture.invalid/file/.*',true,250)")
        assertTrue(requests[1].cacheFirst); assertEquals(250L, requests[1].delay)
        assertEquals("https://fixture.invalid/file/.*", requests[1].sourceRegex); assertNull(requests[1].overrideUrlRegex)
        host.script("source.webViewGetOverrideUrl(null,'$base/page',null, 'https://fixture.invalid/redirect/.*',false,123)")
        assertEquals(123L, requests[2].delay); assertFalse(requests[2].cacheFirst)
        assertEquals("https://fixture.invalid/redirect/.*", requests[2].overrideUrlRegex)
        host.script("java.webView('<p>fixture</p>',null,null)")
        assertEquals(base, requests[3].url)
        assertNull(requests[3].script)
    }

    @Test fun snifferUsesWholeUrlMatchingAndReturnsUrlAsBodyWithOriginalResponseAddress() {
        val capture = SourceWebCapture(SourceWebRequest("$base/start", sourceRegex = "https://fixture.invalid/resource/.*",
            overrideUrlRegex = "https://fixture.invalid/next/.*"))
        assertTrue(capture.active)
        assertNull(capture.resource("$base/not-a-resource"))
        assertNull(capture.resource("https://other.invalid/?to=$base/resource/book"))
        val resource = capture.resource("$base/resource/book")!!
        assertEquals("$base/start", resource.url); assertEquals("$base/resource/book", resource.body)
        val redirect = capture.navigation("$base/next/book")!!
        assertEquals("$base/start", redirect.url); assertEquals("$base/next/book", redirect.body)
        assertNull(capture.navigation("$base/resource/book"))
        assertFalse(SourceWebCapture(SourceWebRequest(base)).active)
    }
}
