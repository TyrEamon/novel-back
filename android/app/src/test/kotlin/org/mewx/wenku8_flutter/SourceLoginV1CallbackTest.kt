package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceLoginV1CallbackTest {
    private val base = "https://fixture.invalid"
    private val state = SourceState()
    private fun engine(ui: String = """[{"name":"账号","type":"text","default":"默认"},{"name":"密码","type":"password"},{"name":"获取","type":"button","viewName":"'获取验证码'","action":"send()"}]""") = BookSourceEngine(mapOf(
        "bookSourceUrl" to base, "loginUi" to ui,
        "loginUrl" to "@js:function login(){} function send(){java.upLoginData({'账号':'已更新','获取':'重新发送'});source.refreshExplore();}"
    ), SourceRun(state = state, fetch = { _, _, _, _ -> error("No networking in login fixture") }))

    @Test fun legacyCallbacksUpdateFieldsAndButtonLabelsWithoutClosing() {
        val result = engine().execute("login", key = "send()", book = mapOf("loginInfo" to mapOf("账号" to "原输入", "密码" to "fixture-only"))) as Map<*, *>
        assertEquals(1, result["version"])
        assertEquals(true, result["refreshExplore"])
        val info = result["info"] as Map<*, *>
        assertEquals("已更新", info["账号"])
        assertEquals("fixture-only", info["密码"])
        assertFalse(info.containsKey("获取"))
        assertEquals("重新发送", ((result["rows"] as List<*>).last() as Map<*, *>)["label"])
        assertFalse(result.containsKey("close"))
    }

    @Test fun nullUpdateResetsDefaultsAndAnotherActionCanRebuildTheForm() {
        val reset = engine().execute("login", key = "java.upLoginData(null)", book = mapOf("loginInfo" to mapOf("账号" to "旧值", "密码" to "fixture-only"))) as Map<*, *>
        assertEquals("默认", (reset["info"] as Map<*, *>)["账号"])
        assertEquals("", (reset["info"] as Map<*, *>)["密码"])
        val ui = """@js:source.get('step')==='code' ? [{name:'验证码',type:'text'}] : [{name:'账号',type:'text'}]"""
        val rebuild = engine(ui).execute("login", key = "source.put('step','code');java.reLoginView(true)",
            book = mapOf("loginInfo" to mapOf("账号" to "原输入"))) as Map<*, *>
        assertEquals("验证码", ((rebuild["rows"] as List<*>).single() as Map<*, *>)["name"])
    }
}
