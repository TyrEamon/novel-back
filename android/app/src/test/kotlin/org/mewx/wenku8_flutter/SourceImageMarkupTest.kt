package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceImageMarkupTest {
    private fun resolve(url: String) = BookSourceEngine.absolute(url, "https://fixture.invalid/chapter")
    @Test fun markdownImagesKeepAllSurroundingProseAndBalancedParentheses() {
        val before = "插图前的每个字都要保留。".repeat(50)
        val after = "插图后的每个字也要保留。".repeat(50)
        val input = "$before\n\n![图片](/figure(1).png)\n\n$after"
        val output = SourceImageMarkup.readerImages(input, ::resolve)
        assertTrue(output.startsWith(before)); assertTrue(output.endsWith(after))
        assertTrue(output.contains("<!--image-->https://fixture.invalid/figure(1).png<!--image-->"))
        assertFalse(output.contains("![图片]"))
    }
    @Test fun htmlImageWrappedInMarkdownDoesNotLeaveBrokenSyntax() {
        val input = "前文\n![图片](\n\n<!--image-->https://fixture.invalid/one.jpg<!--image-->\n\n)\n后文"
        val output = SourceImageMarkup.readerImages(input, ::resolve)
        assertTrue(output.contains("前文\n<!--image-->https://fixture.invalid/one.jpg<!--image-->\n后文"))
    }
    @Test fun incompleteMarkdownIsKeptRatherThanConsumingLaterProse() {
        val input = "前文\n![图片](missing\n\n后面几百字。".repeat(30)
        assertEquals(input, SourceImageMarkup.readerImages(input, ::resolve))
    }
    @Test fun markdownImageQueryIsPartOfTheImageNotTheStory() {
        val after = "插图之后的正文。".repeat(80)
        val output = SourceImageMarkup.readerImages("前文\n![图](/figure.jpg?size=large&v=2)\n$after", ::resolve)
        assertTrue(output.contains("<!--image-->https://fixture.invalid/figure.jpg?size=large&v=2<!--image-->"))
        assertTrue(output.endsWith(after))
        assertFalse(output.contains("![图]("))
    }
    @Test fun sourceContentUsesTheSameBoundaryForJsonRulesAndMainJs() {
        val content = "前文\n![图](/one.jpg)\n后文"
        val json = mapOf("bookSourceUrl" to "https://fixture.invalid", "ruleContent" to mapOf("content" to "body@text"))
        val first = BookSourceEngine(json, SourceRun(fetch = { url, _, _, _ -> SourceReply(url, "<body>$content</body>") })).execute("content", "https://fixture.invalid/chapter").toString()
        val script = mapOf("bookSourceUrl" to "https://fixture.invalid", "mainJs" to "function getContent(){return '前文\\n![图](/one.jpg)\\n后文'}")
        val second = BookSourceEngine(script, SourceRun(fetch = { _, _, _, _ -> error("no request") })).execute("content", "https://fixture.invalid/chapter").toString()
        for (output in listOf(first, second)) {
            assertTrue(output.contains("前文")); assertTrue(output.contains("后文"))
            assertTrue(output.contains("<!--image-->https://fixture.invalid/one.jpg<!--image-->"))
        }
    }
}
