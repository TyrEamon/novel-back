package org.mewx.wenku8_flutter

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin

/** Attach app bridges even when Android creates the shared engine for a media service first. */
class WenkuApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val process = if (android.os.Build.VERSION.SDK_INT >= 28) getProcessName() else {
            (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager).runningAppProcesses
                ?.firstOrNull { it.pid == android.os.Process.myPid() }?.processName
        }
        if (process?.endsWith(":book_sources") == true) {
            if (android.os.Build.VERSION.SDK_INT >= 28) android.webkit.WebView.setDataDirectorySuffix("book_sources")
            return
        }
        attachWenkuEnginePlugins(AudioServicePlugin.getFlutterEngine(this))
    }
}
