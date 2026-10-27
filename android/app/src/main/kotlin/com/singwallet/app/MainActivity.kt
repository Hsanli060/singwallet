package com.singwallet.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.singwallet.app.bridge.CaptureResult
import com.singwallet.app.bridge.ImageSourceKind
import com.singwallet.app.bridge.NativeCaptureFlutterApi
import com.singwallet.app.bridge.NativeCaptureHostApi
import com.singwallet.app.bridge.NativeCaptureHostApiImpl
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_CODE_MEDIA_PERMISSION = 10042
    }

    private var hostApi: NativeCaptureHostApiImpl? = null
    private var flutterApi: NativeCaptureFlutterApi? = null
    private var screenshotObserver: ScreenshotContentObserver? = null
    private val pendingDispatches = mutableListOf<CaptureResult>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ingestionExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var hasRequestedMediaPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val api = NativeCaptureHostApiImpl(applicationContext)
        hostApi = api
        NativeCaptureHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, api)

        val flApi = NativeCaptureFlutterApi(flutterEngine.dartExecutor.binaryMessenger)
        flutterApi = flApi

        // Register background MediaStore observer for system screenshots (e.g. Xiaomi HyperOS Back-Tap)
        registerScreenshotObserver()
        ensureMediaReadPermissionIfNeeded()

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

    private fun registerScreenshotObserver() {
        if (screenshotObserver != null) return

        val observer = ScreenshotContentObserver(
            context = applicationContext,
            mainHandler = mainHandler
        ) { screenshotUri ->
            handleSystemScreenshotUri(screenshotUri)
        }

        try {
            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                observer
            )
            screenshotObserver = observer
        } catch (_: SecurityException) {
            // Do not crash if media permission is restricted by OEM ROM prior to runtime grant
            observer.dispose()
        } catch (_: Exception) {
            observer.dispose()
        }
    }

    private fun unregisterScreenshotObserver() {
        val observer = screenshotObserver ?: return
        screenshotObserver = null
        try {
            contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {
            // Safely ignore if already unregistered
        }
        observer.dispose()
    }

    private fun ensureMediaReadPermissionIfNeeded() {
        if (hasRequestedMediaPermission) return
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

        try {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                hasRequestedMediaPermission = true
                requestPermissions(arrayOf(permission), REQUEST_CODE_MEDIA_PERMISSION)
            }
        } catch (_: Exception) {
            // Ignore in headless / instrumentation environments
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_MEDIA_PERMISSION &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            registerScreenshotObserver()
        }
    }

    private fun handleSystemScreenshotUri(uri: Uri) {
        if (ingestionExecutor.isShutdown) return
        ingestionExecutor.execute {
            val api = hostApi ?: NativeCaptureHostApiImpl(applicationContext)
            val capture = api.ingestSharedImageUri(uri, ImageSourceKind.SYSTEM_SHARE)
            if (capture != null) {
                mainHandler.post {
                    dispatchCaptureToFlutter(capture)
                }
            }
        }
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
                    dispatchCaptureToFlutter(capture)
                }
            }
        }
    }

    private fun dispatchCaptureToFlutter(capture: CaptureResult) {
        val fl = flutterApi
        if (fl != null) {
            fl.onExternalCaptureReceived(capture) { /* ack */ }
        } else {
            synchronized(pendingDispatches) {
                pendingDispatches.add(capture)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unregisterScreenshotObserver()
        NativeCaptureHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        flutterApi = null
        hostApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        unregisterScreenshotObserver()
        mainHandler.removeCallbacksAndMessages(null)
        ingestionExecutor.shutdownNow()
        super.onDestroy()
    }
}
