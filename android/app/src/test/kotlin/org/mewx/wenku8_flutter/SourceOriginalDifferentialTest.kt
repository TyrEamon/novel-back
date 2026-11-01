package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import io.legado.app.model.analyzeRule.AnalyzeByJSoup as OriginalHtml
import io.legado.app.model.analyzeRule.AnalyzeByJSonPath as OriginalJson
import io.legado.app.model.analyzeRule.AnalyzeByXPath as OriginalXPath
import io.legado.app.model.analyzeRule.AnalyzeByRegex as OriginalRegex
import org.mewx.wenku8_flutter.legado.AnalyzeByJSoup as AdaptedHtml
import org.mewx.wenku8_flutter.legado.AnalyzeByJSonPath as AdaptedJson
import org.mewx.wenku8_flutter.legado.AnalyzeByXPath as AdaptedXPath
import org.mewx.wenku8_flutter.legado.AnalyzeByRegex as AdaptedRegex

/** Run identical rules on separately compiled original and adapted selectors.
 * Original files: Legado 3046111c1718e7b67c2ad468e54edf295ec05820 (GPL-3.0).
 * Test harness only replaces Android TextUtils.join and debug logging. */
class SourceOriginalDifferentialTest {
    @Test fun htmlDefaultCssRangesAttributesAndCombinationsMatchOriginal() {
        val html="<main><ul>"+(0..6).joinToString(""){"<li class='row'><a href='/b/$it'>书 $it</a><i>$it</i></li>"}+"</ul><p>独立正文</p><script>data</script></main>"
        val a=OriginalHtml(html);val b=AdaptedHtml(html)
        val selectors=listOf("tag.li","class.row","tag.a","@CSS:li:nth-child(odd)","tag.li[1:4]","tag.li[-1:0:2]","tag.li[!0,-1]","tag.li.0:3")
        for (selector in selectors) for (field in listOf("text","html","all","href")) {
            val rule="$selector@$field"; assertEquals(rule,a.getStringList(rule),b.getStringList(rule))
        }
        for (rule in listOf("tag.a@text&&tag.i@text","tag.a@text%%tag.i@text","tag.q@text||tag.p@text","tag.script@html"))
            assertEquals(rule,a.getStringList(rule),b.getStringList(rule))
    }
    @Test fun jsonFiltersNestedTemplatesAndCombinationsMatchOriginal() {
        val input="""{"items":[{"name":"甲","n":1,"v":2},{"name":"乙","n":2,"v":1}],"empty":[],"nested":{"text":"a}b"}}"""
        val a=OriginalJson(input);val b=AdaptedJson(input)
        for(rule in listOf("$.items[*].name","$.items[?(@.n==1 && @.v==2)].name","$.items[?(@.n==1 || @.v==1)].name",
            "$.empty||$.items[*].name","$.items[0].name&&$.items[1].name","{$.items[0].name}:{$.nested.text}","$.items[0].n")) {
            assertEquals(rule,a.getStringList(rule),b.getStringList(rule));assertEquals(rule,a.getString(rule),b.getString(rule))
        }
    }
    @Test fun xpathNodeAndAttributeOperationsMatchOriginal() {
        val input="<ul><li><a href='/a'>甲</a></li><li><a href='/b'>乙</a></li></ul><p>正文</p>"
        val a=OriginalXPath(input);val b=AdaptedXPath(input)
        for(rule in listOf("//li/a/text()","//li/a/@href","//li[1]","//q/text()||//p/text()","//li/a/text()&&//p/text()","//li/a/text()%%//li/a/@href"))
            assertEquals(rule,a.getStringList(rule),b.getStringList(rule))
    }
    @Test fun regexCaptureAndMultiStageOperationsMatchOriginal() {
        val input="<section><a href='/a'>甲</a><a href='/b'>乙</a></section>"
        for(rules in listOf(arrayOf("<a href='(.*?)'>(.*?)</a>"),arrayOf("<section>(.*?)</section>","<a href='(.*?)'>(.*?)</a>"))) {
            assertEquals(OriginalRegex.getElements(input,rules),AdaptedRegex.getElements(input,rules))
            assertEquals(OriginalRegex.getElement(input,rules),AdaptedRegex.getElement(input,rules))
        }
    }
}
