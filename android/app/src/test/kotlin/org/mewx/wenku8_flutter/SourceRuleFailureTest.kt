package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import javax.net.ssl.SSLException

class SourceRuleFailureTest {
    @Test fun imageHttpFailuresKeepStatusWithoutTheUrlOrResponseBody() {
        val engine = BookSourceEngine(mapOf("bookSourceUrl" to "https://fixture.invalid"),
            SourceRun(fetch = { url, _, _, _ -> SourceReply(url, "private body", 403) }))
        val failure = try {
            engine.image("https://fixture.invalid/image.jpg?token=secret", false)
            error("Expected image failure")
        } catch (failure: SourceImageHttpFailure) { failure }
        assertEquals("书源图片请求未完成（HTTP 403）", sourceRuleFailureMessage(failure))
        val diagnostic = sourceFailureDiagnostic(failure)
        assertTrue(diagnostic.contains("image.http 403"))
        for (secret in listOf("https://", "token", "secret", "private body")) assertFalse(diagnostic.contains(secret))
    }
    @Test fun nestedRuleRequestsReportTheFieldAndSafeFailureCategory() {
        val source = mapOf("bookSourceUrl" to "https://fixture.invalid", "ruleBookInfo" to mapOf(
            "name" to "h1@text", "intro" to "p@text@js:java.get('https://helper.invalid/',null).body()"))
        val engine = BookSourceEngine(source, SourceRun(fetch = { url, _, _, _ ->
            if (url.contains("helper.invalid")) throw SSLException("private request details must stay hidden")
            SourceReply(url, "<h1>星海</h1><p>简介</p>")
        }))
        val detail = engine.execute("detail", "https://fixture.invalid/book") as Map<*, *>
        assertEquals("星海", detail["name"])
        assertEquals("https://fixture.invalid/book", detail["tocUrl"])
        assertEquals(listOf("书源简介：请求的安全连接失败"), detail["ruleWarnings"])
    }

    @Test fun scriptErrorsDoNotExposeScriptOrAccountValues() {
        val failure = SourceRuleFailure("chapterUrl", org.htmlunit.corejs.javascript.EvaluatorException("private account or script text"))
        assertEquals("书源章节目录：JavaScript 规则执行失败", sourceRuleFailureMessage(failure))
    }

    @Test fun diagnosticOmitsMessagesAndScriptFileNames() {
        val inner = IllegalArgumentException("Cookie: private; https://private.invalid/?token=secret")
        inner.stackTrace = arrayOf(StackTraceElement("engine.Rule", "execute", "https://private.invalid/?token=secret", 42))
        val report = sourceFailureDiagnostic(IllegalStateException("account password", inner))
        assertTrue(report.contains("java.lang.IllegalArgumentException"))
        assertTrue(report.contains("at engine.Rule.execute(Native:42)"))
        for (secret in listOf("Cookie", "private", "token", "secret", "password", "https://")) assertFalse(report.contains(secret))
    }
}
