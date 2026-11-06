package com.franco.corriere_audiobook

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge layout for modern HyperOS 3 / Android 16
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)

        // Lock 120Hz refresh rate specifically optimized for POCO F7 display
        optimizeRefreshRateForPocoF7()
    }

    private fun optimizeRefreshRateForPocoF7() {
        try {
            val wm = windowManager
            val curDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                wm.defaultDisplay
            }

            val modes = curDisplay?.supportedModes ?: emptyArray()
            // Locate 120Hz or higher refresh rate mode supported by the POCO F7 panel
            val mode120 = modes.firstOrNull { it.refreshRate >= 119.0f }
            if (mode120 != null) {
                val lp = window.attributes
                lp.preferredDisplayModeId = mode120.modeId
                window.attributes = lp
            }
        } catch (_: Exception) {
            // Graceful fallback to default refresh rate if device display mode API is restricted
        }
    }
}
