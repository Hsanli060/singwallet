package com.singwallet.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.singwallet.app.bridge.CaptureResult
import com.singwallet.app.bridge.ImageSourceKind
import com.singwallet.app.bridge.NativeCaptureFlutterApi
import com.singwallet.app.bridge.NativeCaptureHostApi
import com.singwallet.app.bridge.NativeCaptureHostApiImpl

class MainActivity : FlutterActivity() {
    private var hostApi: NativeCaptureHostApiImpl? = null
    private var flutterApi: NativeCaptureFlutterApi? = null
    private val pendingDispatches = mutableListOf<CaptureResult>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val api = NativeCaptureHostApiImpl(applicationContext)
        hostApi = api
        NativeCaptureHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, api)

        val flApi = NativeCaptureFlutterApi(flutterEngine.dartExecutor.binaryMessenger)
        flutterApi = flApi

        // Handle cold launch share intent
        handleShareIntent(intent)

        // Flush any queued captures once engine is ready
        synchronized(pendingDispatches) {
            for (capture in pendingDispatches) {
                flApi.onExternalCaptureReceived(capture) { /* ack */ }
            }
            pendingDispatches.clear()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("image/") == true) {
            val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }

            if (uri != null) {
                val api = hostApi ?: NativeCaptureHostApiImpl(applicationContext)
                val capture = api.ingestSharedImageUri(uri, ImageSourceKind.SYSTEM_SHARE)
                if (capture != null) {
                    val fl = flutterApi
                    if (fl != null) {
                        fl.onExternalCaptureReceived(capture) { /* ack */ }
                    } else {
                        synchronized(pendingDispatches) {
                            pendingDispatches.add(capture)
                        }
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NativeCaptureHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        flutterApi = null
        hostApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
