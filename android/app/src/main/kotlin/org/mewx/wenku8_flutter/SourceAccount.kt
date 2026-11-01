package org.mewx.wenku8_flutter

/** Optional host extension, not a redefinition of Legado's loginCheckJs.
 * Every request/action must be explicitly declared by the imported rule. */
internal class SourceAccountRules(raw: Any?) {
    private val rules: Map<*, *> = if (raw == null) emptyMap<Any, Any>() else
        raw as? Map<*, *> ?: throw SourceAccountFailure("书源账号扩展应为规则对象")

    private fun section(name: String, required: List<String>): Map<String, Any?>? {
        val raw = rules[name] ?: return null
        val map = (raw as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }
            ?: throw SourceAccountFailure("书源账号扩展的操作规则无效")
        if (required.any { (map[it] as? String).isNullOrBlank() })
            throw SourceAccountFailure("书源账号扩展缺少请求地址或结果规则")
        return map
    }
    fun verify() = section("verify", listOf("url", "loggedIn"))
    fun shelf() = section("shelf", listOf("url", "bookList", "name", "bookUrl"))
    fun checkIn() = section("checkIn", listOf("url", "success"))
    fun capabilities() = mapOf("verify" to (verify() != null), "shelf" to (shelf() != null), "checkIn" to (checkIn() != null))

    companion object {
        fun boolean(value: String): Boolean = when (value.trim().lowercase()) {
            "true", "1" -> true
            "false", "0" -> false
            else -> throw SourceAccountFailure("书源账号结果规则须返回 true／false 或 1／0")
        }
    }
}

internal class SourceAccountFailure(message: String) : RuntimeException(message)

/** Host-owned metadata is encrypted with the existing source session vault.
 * Form values, cookies, and a response-transforming loginCheckJs do not prove login. */
internal object SourceAccountState {
    private const val OWNER = "host-account"
    private const val FRESH_MILLIS = 15 * 60_000L
    fun changed(state: SourceState) { state.remove(OWNER, "validation") }
    fun credentialsChanged(state: SourceState) {
        changed(state)
        state.remove(OWNER, "checkInAt")
    }
    fun submitted(state: SourceState) {
        credentialsChanged(state)
        state.put(OWNER, "submittedAt", System.currentTimeMillis().toString())
    }
    fun verified(state: SourceState, loggedIn: Boolean) {
        state.put(OWNER, "validation", if (loggedIn) "verified" else "signedOut")
        state.put(OWNER, "checkedAt", System.currentTimeMillis().toString())
    }
    fun failed(state: SourceState) { state.put(OWNER, "validation", "error") }
    fun checkedIn(state: SourceState) { state.put(OWNER, "checkInAt", System.currentTimeMillis().toString()) }
    fun checkedInToday(state: SourceState, now: Long = System.currentTimeMillis()): Boolean {
        val last = state.get(OWNER, "checkInAt").toLongOrNull() ?: return false
        fun day(time: Long) = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT).format(java.util.Date(time))
        return day(last) == day(now)
    }
    fun view(source: Map<String, Any?>, state: SourceState, hasCookies: Boolean, now: Long = System.currentTimeMillis()): Map<String, Any?> {
        var configurationError = false
        val capabilities = try { SourceAccountRules(source["ruleAccount"]).capabilities() }
            catch (_: SourceAccountFailure) { configurationError = true; mapOf("verify" to false, "shelf" to false, "checkIn" to false) }
        val submitted = state.get(OWNER, "submittedAt").toLongOrNull()
        val checked = state.get(OWNER, "checkedAt").toLongOrNull()
        val validation = state.get(OWNER, "validation")
        val declaredHeaders = runCatching {
            val raw = source["header"]
            if (raw is Map<*, *>) raw else if (raw is String && raw.trim().startsWith('{'))
                com.google.gson.Gson().fromJson(raw, Map::class.java) else null
        }.getOrNull()
        val hasDeclaredCredential = declaredHeaders?.any { (name, value) ->
            SourceNetwork.sensitive(name.toString()) && !value?.toString().isNullOrBlank()
        } == true
        val hasSession = hasCookies || hasDeclaredCredential || state.get("login", "header").let { it.isNotBlank() && it != "{}" }
        val loginAvailable = !source["loginUrl"]?.toString().isNullOrBlank() ||
            source["loginUi"]?.toString()?.trim()?.let { it.isNotEmpty() && it != "[]" } == true
        val status = when {
            validation == "error" -> "error"
            checked != null && now - checked in 0..FRESH_MILLIS && validation in setOf("verified", "signedOut") -> validation
            hasSession -> "saved"
            submitted != null || checked != null -> "unchecked"
            else -> "none"
        }
        return mapOf("status" to status, "hasSession" to hasSession, "loginAvailable" to loginAvailable,
            "capabilities" to capabilities, "configurationError" to configurationError,
            "checkedAt" to checked, "submittedAt" to submitted,
            "checkInAt" to state.get(OWNER, "checkInAt").toLongOrNull(), "checkedInToday" to checkedInToday(state, now))
    }
}
