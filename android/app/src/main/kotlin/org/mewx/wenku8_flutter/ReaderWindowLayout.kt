package org.mewx.wenku8_flutter

import android.os.Build
import android.view.Window
import android.view.WindowManager
import androidx.core.view.WindowCompat

/** Keep the same edge-to-edge window when status bars disappear. DEFAULT
 * letterboxes pre-Android-15 cutout devices after hide(statusBars), exposing
 * a black strip outside Flutter's surface. Text still uses Flutter safe insets. */
internal object ReaderWindowLayout {
    fun cutoutMode(sdk: Int): Int? = when {
        sdk >= 30 -> WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        sdk >= 28 -> WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        else -> null
    }

    fun apply(window: Window) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= 28) {
            val attributes = window.attributes
            val mode = cutoutMode(Build.VERSION.SDK_INT)!!
            if (attributes.layoutInDisplayCutoutMode != mode) {
                attributes.layoutInDisplayCutoutMode = mode
                window.attributes = attributes
            }
        }
        if (Build.VERSION.SDK_INT >= 29) window.isStatusBarContrastEnforced = false
    }
}
