package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class SourceAccountTest {
    private val source = mapOf<String, Any?>("bookSourceUrl" to "https://fixture.invalid", "bookSourceName" to "自编账号",
        "loginUrl" to "https://fixture.invalid/login", "ruleAccount" to mapOf(
            "verify" to mapOf("url" to "/account", "loggedIn" to "$.loggedIn"),
            "shelf" to mapOf("url" to "/shelf?page={{page}}", "bookList" to "$.books[*]", "name" to "$.name", "bookUrl" to "$.url", "author" to "$.author", "nextPageUrl" to "$.next"),
            "checkIn" to mapOf("url" to "/check-in,{\"method\":\"POST\",\"retry\":3}", "success" to "$.success", "already" to "$.already")))
    private fun view(state: SourceState, cookies: Boolean = false) = SourceAccountState.view(source, state, cookies)

    @Test fun formDefaultsAndCookiePresenceNeverProveLogin() {
        val state = SourceState()
        state.put("login", "info", "{\"account\":\"fixture\",\"password\":\"private\"}")
        assertEquals("none", view(state)["status"])
        assertEquals("saved", view(state, true)["status"])
        assertEquals("saved", SourceAccountState.view(source + ("header" to "{\"Authorization\":\"fixture-private\"}"), state, false)["status"])
        SourceAccountState.submitted(state)
        assertEquals("unchecked", view(state)["status"])
        assertFalse(view(state).toString().contains("private"))
    }
    @Test fun verificationIsExplicitAndExpiresWithoutTreatingNetworkFailureAsLogout() {
        val state = SourceState()
        fun engine(body: String, code: Int = 200) = BookSourceEngine(source, SourceRun(state = state,
            fetch = { url, _, _, _ -> SourceReply(url, body, code) }))
        assertEquals(true, engine("{\"loggedIn\":true}").execute("accountVerify"))
        assertEquals("verified", view(state)["status"])
        val checkedAt = view(state)["checkedAt"] as Long
        assertEquals("unchecked", SourceAccountState.view(source, state, false, checkedAt + 16*60_000)["status"])
        assertEquals(false, engine("sign in", 401).execute("accountVerify"))
        assertEquals("signedOut", view(state, true)["status"])
        assertTrue(runCatching { engine("blocked", 403).execute("accountVerify") }.isFailure)
        assertEquals("error", view(state, true)["status"])
        assertTrue(runCatching { engine("{\"loggedIn\":\"username is not a boolean\"}").execute("accountVerify") }.isFailure)
        assertEquals("error", view(state)["status"])
    }
    @Test fun unrelatedLoginCheckJsIsNotReinterpretedAsAccountVerification() {
        val legacy = source - "ruleAccount" + ("loginCheckJs" to "result")
        var requests = 0
        val state = SourceState()
        val engine = BookSourceEngine(legacy, SourceRun(state = state, fetch = { _, _, _, _ -> requests++; error("must not fetch") }))
        assertTrue(runCatching { engine.execute("accountVerify") }.exceptionOrNull() is SourceAccountFailure)
        assertEquals(0, requests)
        assertEquals(mapOf("verify" to false, "shelf" to false, "checkIn" to false), SourceAccountState.view(legacy, state, true)["capabilities"])
    }
    @Test fun credentialsAndSessionChangesInvalidatePriorVerification() {
        val state = SourceState()
        state.put("login", "header", "{\"Authorization\":\"fixture\"}")
        SourceAccountState.verified(state, true)
        state.put("book:one", "name", "book data")
        assertEquals("verified", view(state)["status"])
        state.put("login", "header", "{\"Authorization\":\"changed\"}")
        assertEquals("saved", view(state)["status"])
        SourceAccountState.verified(state, true)
        SourceAccountState.changed(state)
        assertEquals("saved", view(state)["status"])
        SourceAccountState.checkedIn(state)
        state.remove("login", "header")
        assertFalse(view(state)["checkedInToday"] as Boolean)
    }
    @Test fun checkInHasNoAutomaticRetryAndRepeatedSuccessDoesNotSendAnotherMutation() {
        val state = SourceState(); var calls = 0
        val engine = BookSourceEngine(source, SourceRun(state = state, fetch = { url, method, _, _ ->
            calls++; assertEquals("POST", method); SourceReply(url, "{\"success\":true,\"already\":false}") }))
        assertEquals(mapOf("already" to false), engine.execute("accountCheckIn"))
        assertEquals(mapOf("already" to true), engine.execute("accountCheckIn"))
        assertEquals(1, calls)
        assertTrue(view(state)["checkedInToday"] as Boolean)
        assertNotEquals("verified", view(state)["status"])
        var failures = 0
        val failing = BookSourceEngine(source, SourceRun(fetch = { _, _, _, _ -> failures++; throw java.io.IOException("private") }))
        assertTrue(runCatching { failing.execute("accountCheckIn") }.isFailure)
        assertEquals(1, failures)
    }
    @Test fun checkInFailureAndCancellationNeverClaimSuccess() {
        val state = SourceState()
        val engine = BookSourceEngine(source, SourceRun(state = state, fetch = { url, _, _, _ -> SourceReply(url, "{\"success\":false,\"already\":false}") }))
        assertTrue(runCatching { engine.execute("accountCheckIn") }.isFailure)
        assertFalse(SourceAccountState.checkedInToday(state))
        val cancelled = BookSourceEngine(source, SourceRun(state = state, fetch = { _, _, _, _ -> throw CancellationException() }))
        assertTrue(runCatching { cancelled.execute("accountVerify") }.exceptionOrNull() is CancellationException)
        assertEquals("none", view(state)["status"])
    }
    @Test fun shelfUsesNormalBookRulesAndExplicitPagination() {
        val engine = BookSourceEngine(source, SourceRun(fetch = { url, _, _, _ ->
            assertTrue(url.endsWith("/shelf?page=2"))
            SourceReply(url, """{"books":[{"name":"星海","url":"/book/one","author":"作者：自编作者"}],"next":"/shelf?page=3"}""") }))
        val result = engine.execute("accountShelf", page = 2) as Map<*, *>
        val book = (result["items"] as List<*>).single() as Map<*, *>
        assertEquals("星海", book["name"])
        assertEquals("自编作者", book["author"])
        assertEquals("https://fixture.invalid/book/one", book["bookUrl"])
        assertEquals("https://fixture.invalid/shelf?page=3", result["nextUrl"])
        assertEquals(true, result["hasMore"])
    }
    @Test fun malformedCapabilitiesAndMissingBookFieldsAreNotSilentlySuccessful() {
        val invalid = source + ("ruleAccount" to mapOf("verify" to mapOf("url" to "/account")))
        assertEquals(true, SourceAccountState.view(invalid, SourceState(), false)["configurationError"])
        val engine = BookSourceEngine(source, SourceRun(fetch = { url, _, _, _ -> SourceReply(url, """{"books":[{"name":"星海"}]}""") }))
        assertTrue(runCatching { engine.execute("accountShelf") }.exceptionOrNull() is SourceAccountFailure)
    }
    @Test fun disabledSourceDoesNotExecuteAccountRequests() {
        var calls = 0
        val engine = BookSourceEngine(source + ("enabled" to false), SourceRun(fetch = { _, _, _, _ -> calls++; error("must not fetch") }))
        for (operation in listOf("accountVerify", "accountShelf", "accountCheckIn")) {
            assertTrue(runCatching { engine.execute(operation) }.exceptionOrNull() is SourceAccountFailure)
        }
        assertEquals(0, calls)
    }
}
