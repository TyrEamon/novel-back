package org.mewx.wenku8_flutter

import java.io.InterruptedIOException
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import org.htmlunit.corejs.javascript.RhinoException

/** Error context consists of engine-owned labels, never source code or URLs. */
internal class SourceRuleFailure(val field: String, cause: Exception) : RuntimeException(cause)
internal class SourceHeaderFailure : IllegalArgumentException("书源请求头格式无效，请检查书源请求头或重新登录")
internal class SourceImageHttpFailure(val status: Int) : IllegalStateException("书源图片请求未完成（HTTP $status）")

/** Local diagnostics contain native types/frames only. Exception messages and
 * script filenames may include URLs, credentials or content and are excluded. */
internal fun sourceFailureDiagnostic(failure: Throwable): String = buildString {
    val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
    var current: Throwable? = failure
    var depth = 0
    while (current != null && depth++ < 6 && seen.add(current)) {
        append(if (depth == 1) "source.failure " else "caused-by ")
        append(current.javaClass.name).append('\n')
        if (current is SourceImageHttpFailure) append("image.http ").append(current.status).append('\n')
        current.stackTrace.take(8).forEach { frame ->
            append("at ").append(frame.className).append('.').append(frame.methodName)
                .append("(Native:").append(frame.lineNumber).append(")\n")
        }
        current = current.cause
    }
}

internal fun sourceRuleFailureMessage(failure: Exception): String? {
    val chain = generateSequence<Throwable>(failure) { it.cause }.toList()
    val field = chain.filterIsInstance<SourceRuleFailure>().firstOrNull()?.field
    val label = when (field) {
        "name" -> "书名"
        "author" -> "作者"
        "intro" -> "简介"
        "coverUrl" -> "封面"
        "tocUrl" -> "目录地址"
        "lastChapter" -> "最新章节"
        "kind" -> "标签"
        "wordCount" -> "字数"
        "chapterName", "chapterUrl", "isVolume" -> "章节目录"
        else -> null
    }
    val reason = when {
        chain.any { it is SourceImageHttpFailure } -> return chain.filterIsInstance<SourceImageHttpFailure>().first().message
        chain.any { it is SourceHeaderFailure } -> "请求头格式无效，请检查书源请求头或重新登录"
        chain.any { it is SourceAccountFailure } -> return chain.filterIsInstance<SourceAccountFailure>().first().message
        chain.any { it is UnknownHostException } -> "请求的域名无法解析"
        chain.any { it is SSLException } -> "请求的安全连接失败"
        chain.any { it is InterruptedIOException } -> "请求超时"
        chain.any { it is java.io.IOException } -> "网络请求未完成"
        chain.any { it.message == "书源执行超时" } -> "规则执行超时"
        chain.any { it is RhinoException } -> "JavaScript 规则执行失败"
        else -> if (label != null) "规则执行未完成" else return null
    }
    return if (label != null) "书源${label}：$reason" else "书源$reason"
}
