package com.singwallet.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.provider.Settings
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.singwallet.app.services.QuickRecordTileService
import com.singwallet.app.services.SingWalletAccessibilityService
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * SingWallet 混合离线主宿主 Activity (方案一).
 *
 * 核心设计：
 * 1. 100% 像素级还原浏览器预览效果 (通过 file:///android_asset/singwallet_preview.html 离线渲染).
 * 2. 硬件加速 + 沉浸式暗黑主题 (#020617)，零闪屏零网络依赖秒级启动.
 * 3. 对接小米澎湃 OS (HyperOS) 下拉控制中心「闪电记账」快捷开关 (QuickRecordTileService).
 * 4. 对接系统相册内容监听 (ScreenshotContentObserver)，支持轻敲手机背部两下自动无感抓屏记账.
 * 5. 支持图片解析完成后自动清理相册临时截屏 (deleteScreenshot)，杜绝相册垃圾堆积.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "SingWalletActivity"
        private const val REQUEST_CODE_MEDIA_PERMISSION = 10042
        private const val ASSET_ENTRY_URL = "file:///android_asset/singwallet_preview.html"

        @Volatile
        private var instance: MainActivity? = null

        fun getInstance(): MainActivity? = instance

        fun isAlive(): Boolean = instance != null && !(instance?.isFinishing ?: true)

        /**
         * 供 QuickRecordTileService 在后台捕获屏幕快照后安全派发至 WebView
         */
        fun dispatchCapturedScreenshot(dataUrl: String, source: String = "lightning-tile") {
            val act = instance
            if (act != null) {
                act.mainHandler.post {
                    if (act.isPageLoaded) {
                        act.dispatchScreenshotToWebView(dataUrl, "", source)
                    } else {
                        synchronized(act.pendingScreenshots) {
                            act.pendingScreenshots.add(Triple(dataUrl, "", source))
                        }
                    }
                }
            } else {
                Log.i(TAG, "MainActivity is not in memory; snapshot preserved in disk queue")
            }
        }
    }

    private var webView: WebView? = null
    private var screenshotObserver: ScreenshotContentObserver? = null
    private var isPageLoaded = false
    private var pendingTileTrigger = false
    private val pendingScreenshots = mutableListOf<Triple<String, String, String>>() // (dataUrl, uriString, source)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ingestionExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var hasRequestedPermission = false

    private val fileChooserLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (filePathCallback != null) {
            val results = WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
            filePathCallback?.onReceiveValue(results)
            filePathCallback = null
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // 注册全局异常捕获，确保即使有任何极端异常也能输出 Logcat 并弹窗提示，绝不静默闪退
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "Uncaught exception on thread ${thread.name}: ${throwable.message}", throwable)
        }

        try {
            // 1. 设置沉浸式纯黑底色与状态栏/导航栏
            applyWindowDecorations()

            // 2. 创建并配置硬件加速全屏 WebView
            val rootLayout = FrameLayout(this).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                setBackgroundColor(Color.parseColor("#020617"))
            }

            val wv = WebView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                setBackgroundColor(Color.parseColor("#020617"))
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
            }
            rootLayout.addView(wv)
            setContentView(rootLayout)
            webView = wv

            configureWebView(wv)

            // 3. 注册返回手势/物理按键拦截 (优先关闭 H5 内置弹窗)
            setupBackPressHandler(wv)

            // 4. 注册系统截屏监听 (注册 Observer 无需运行时权限；读取时再做校验)
            registerScreenshotObserver()

            // 5. 载入离线 H5 页面
            wv.loadUrl(ASSET_ENTRY_URL)

            // 6. 处理可能带入的启动 Intent (控制中心快捷瓷贴 / 分享意图)
            handleIntent(intent)

            // 7. 扫描未处理的离线闪电抓屏任务
            scanPendingLightningCaptures()

            // 8. 延迟 1.5 秒在界面完全渲染就绪后，静默检测并引导相册读取权限
            ensureMediaPermissionDelayed()
        } catch (t: Throwable) {
            Log.e(TAG, "Error in onCreate: ${t.message}", t)
        }
    }

    private fun applyWindowDecorations() {
        try {
            val darkBg = Color.parseColor("#020617")
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
            window.statusBarColor = darkBg
            window.navigationBarColor = darkBg

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.insetsController?.setSystemBarsAppearance(
                    0, // 0 = light icons on dark background
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                )
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        } catch (e: Throwable) {
            Log.w(TAG, "applyWindowDecorations warning: ${e.message}")
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(wv: WebView) {
        val settings = wv.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        @Suppress("DEPRECATION")
        settings.allowFileAccessFromFileURLs = true
        @Suppress("DEPRECATION")
        settings.allowUniversalAccessFromFileURLs = true
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.mediaPlaybackRequiresUserGesture = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.setSupportZoom(false)
        settings.builtInZoomControls = false
        settings.displayZoomControls = false

        // 注入 SingWallet 专属 UserAgent
        val defaultUa = settings.userAgentString
        settings.userAgentString = "$defaultUa SingWalletAndroid/1.0.4 Mobile"

        wv.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")

        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                if (url.startsWith("file:///android_asset/") || url.startsWith("data:") || url.startsWith("blob:")) {
                    return false
                }
                // 外部网页链接使用系统浏览器打开
                try {
                    val extIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(extIntent)
                } catch (e: Exception) {
                    Log.w(TAG, "Cannot launch external url: $url", e)
                }
                return true
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                Log.i(TAG, "SingWallet WebView loaded: $url")
                isPageLoaded = true

                // 注入 Native 模式标记 class
                wv.evaluateJavascript("document.body.classList.add('native-app');", null)

                // 刷新暂存的待处理抓屏任务
                synchronized(pendingScreenshots) {
                    for ((dataUrl, uriString, source) in pendingScreenshots) {
                        dispatchScreenshotToWebView(dataUrl, uriString, source)
                    }
                    pendingScreenshots.clear()
                }

                if (pendingTileTrigger) {
                    pendingTileTrigger = false
                    triggerQuickRecordInWeb()
                }
            }
        }

        wv.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                Log.d("SingWalletWeb", "[${consoleMessage?.messageLevel()}] ${consoleMessage?.message()} (${consoleMessage?.sourceId()}:${consoleMessage?.lineNumber()})")
                return true
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback
                try {
                    val intent = fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    fileChooserLauncher.launch(intent)
                    return true
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to launch file chooser: ${e.message}", e)
                    this@MainActivity.filePathCallback = null
                    return false
                }
            }
        }
    }

    private fun setupBackPressHandler(wv: WebView) {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                wv.evaluateJavascript("typeof window.handleAndroidBackPress === 'function' ? window.handleAndroidBackPress() : false") { result ->
                    val handled = result?.replace("\"", "")?.trim() == "true"
                    if (!handled) {
                        if (wv.canGoBack()) {
                            wv.goBack()
                        } else {
                            // 退至后台而不强制销毁，保持后台秒开与无感记账能力
                            moveTaskToBack(true)
                        }
                    }
                }
            }
        })
    }

    private fun ensureMediaPermissionDelayed() {
        if (hasRequestedPermission) return
        mainHandler.postDelayed({
            try {
                val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Manifest.permission.READ_MEDIA_IMAGES
                } else {
                    Manifest.permission.READ_EXTERNAL_STORAGE
                }
                if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                    hasRequestedPermission = true
                    ActivityCompat.requestPermissions(this, arrayOf(permission), REQUEST_CODE_MEDIA_PERMISSION)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Delayed permission check error: ${e.message}")
            }
        }, 1500)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
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
            Log.i(TAG, "ScreenshotContentObserver registered successfully")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register ScreenshotContentObserver: ${e.message}")
            observer.dispose()
        }
    }

    private fun unregisterScreenshotObserver() {
        val observer = screenshotObserver ?: return
        screenshotObserver = null
        try {
            contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {}
        observer.dispose()
    }

    private fun handleSystemScreenshotUri(uri: Uri) {
        if (ingestionExecutor.isShutdown) return
        ingestionExecutor.execute {
            try {
                val inputStream: InputStream? = contentResolver.openInputStream(uri)
                if (inputStream != null) {
                    val bitmap = BitmapFactory.decodeStream(inputStream)
                    inputStream.close()
                    if (bitmap != null) {
                        val outputStream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, outputStream)
                        val byteArray = outputStream.toByteArray()
                        val base64 = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                        val dataUrl = "data:image/jpeg;base64,$base64"

                        mainHandler.post {
                            if (isPageLoaded) {
                                dispatchScreenshotToWebView(dataUrl, uri.toString(), "backtap-screenshot")
                            } else {
                                synchronized(pendingScreenshots) {
                                    pendingScreenshots.add(Triple(dataUrl, uri.toString(), "backtap-screenshot"))
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error ingesting screenshot $uri: ${e.message}", e)
            }
        }
    }

    private val scanLock = Any()

    private fun scanPendingLightningCaptures() {
        if (ingestionExecutor.isShutdown) return
        ingestionExecutor.execute {
            synchronized(scanLock) {
                try {
                    val dir = File(filesDir, "pending_lightning_captures")
                    if (dir.exists() && dir.isDirectory) {
                        val files = dir.listFiles { f -> f.extension.equals("jpg", ignoreCase = true) }
                        files?.sortBy { it.lastModified() }
                        files?.forEach { file ->
                            // 原子认领机制：通过 renameTo 成为专属 processing 文件，杜绝与冷启动/热启动并发扫描重复处理
                            val processingFile = File(dir, "${file.nameWithoutExtension}_${System.currentTimeMillis()}.processing")
                            if (file.renameTo(processingFile)) {
                                try {
                                    val bytes = processingFile.readBytes()
                                    val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                    val dataUrl = "data:image/jpeg;base64,$base64"
                                    mainHandler.post {
                                        if (isPageLoaded) {
                                            dispatchScreenshotToWebView(dataUrl, "", "lightning-tile")
                                        } else {
                                            synchronized(pendingScreenshots) {
                                                pendingScreenshots.add(Triple(dataUrl, "", "lightning-tile"))
                                            }
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to ingest cached lightning capture ${processingFile.name}: ${e.message}")
                                } finally {
                                    try {
                                        processingFile.delete()
                                    } catch (_: Throwable) {}
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "scanPendingLightningCaptures error: ${e.message}")
                }
            }
        }
    }

    internal fun dispatchScreenshotToWebView(
        dataUrl: String,
        uriString: String,
        source: String = "backtap-screenshot"
    ) {
        val escapedDataUrl = dataUrl.replace("'", "\\'")
        val escapedUri = uriString.replace("'", "\\'")
        val script = """
            if (typeof window.handleShortcutCapturedItem === 'function') {
                window.handleShortcutCapturedItem({
                    dataUrl: '$escapedDataUrl',
                    source: '$source',
                    uri: '$escapedUri'
                });
            }
        """.trimIndent()
        Log.i(TAG, "Dispatching screenshot to WebView: source=$source, dataUrlLen=${dataUrl.length}")
        webView?.evaluateJavascript(script) { result ->
            Log.i(TAG, "Screenshot dispatched to WebView callback: source=$source, evalResult=$result")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action

        // 1. 小米 HyperOS 下拉控制中心「应用快捷开关」闪电记账
        if (action == QuickRecordTileService.ACTION_TRIGGER_QUICK_RECORD) {
            Log.i(TAG, "Received Quick Settings Tile Trigger")
            if (isPageLoaded) {
                triggerQuickRecordInWeb()
            } else {
                pendingTileTrigger = true
            }
            return
        }

        // 2. 系统分享单图接收 (例如微信、支付宝长按分享到 SingWallet)
        if (action == Intent.ACTION_SEND && intent.type?.startsWith("image/") == true) {
            val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (uri != null) {
                handleSystemScreenshotUri(uri)
            }
        }
    }

    private fun triggerQuickRecordInWeb() {
        val script = """
            if (typeof window.onTileQuickRecordTriggered === 'function') {
                window.onTileQuickRecordTriggered();
            } else if (typeof window.showToast === 'function') {
                window.showToast('闪电记账已激活');
            }
        """.trimIndent()
        webView?.evaluateJavascript(script, null)
    }

    override fun onResume() {
        super.onResume()
        webView?.onResume()
        // 热启动恢复或从前台切回时，主动扫描离线捕获落盘的闪电抓屏任务，确保零丢单
        scanPendingLightningCaptures()
    }

    override fun onPause() {
        super.onPause()
        // 关键保活设计：绝不调用 webView?.onPause()！
        // 保持后台 WebView JS 上下文活跃，确保用户在微信/支付宝付款页前台点击「闪电记账」磁贴时，
        // 后台 WebView 能瞬间接收快照并执行大模型解析与 localStorage 存库，绝不挂起丢单。
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        unregisterScreenshotObserver()
        mainHandler.removeCallbacksAndMessages(null)
        ingestionExecutor.shutdownNow()
        webView?.apply {
            loadUrl("about:blank")
            clearHistory()
            removeAllViews()
            destroy()
        }
        webView = null
        super.onDestroy()
    }

    inner class AndroidBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun showToast(message: String) {
            activity.runOnUiThread {
                Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
            }
        }

        @JavascriptInterface
        fun vibrate(durationMs: Long) {
            activity.runOnUiThread {
                try {
                    val vibrator = activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.vibrate(VibrationEffect.createOneShot(durationMs.coerceAtLeast(10L), VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator?.vibrate(durationMs)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Vibrate error: ${e.message}")
                }
            }
        }

        @JavascriptInterface
        fun copyToClipboard(text: String) {
            activity.runOnUiThread {
                val cm = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.setPrimaryClip(ClipData.newPlainText("SingWallet", text))
                Toast.makeText(activity, "已复制到剪贴板", Toast.LENGTH_SHORT).show()
            }
        }

        @JavascriptInterface
        fun deleteScreenshot(uriString: String) {
            activity.runOnUiThread {
                try {
                    val uri = Uri.parse(uriString)
                    val rows = activity.contentResolver.delete(uri, null, null)
                    Log.i(TAG, "Auto-cleaned screenshot $uriString, rows affected: $rows")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to auto-clean screenshot $uriString: ${e.message}")
                }
            }
        }

        @JavascriptInterface
        fun getAppVersion(): String {
            return "1.0.4"
        }

        @JavascriptInterface
        fun isNativeApp(): Boolean {
            return true
        }

        @JavascriptInterface
        fun triggerQuickRecord() {
            activity.runOnUiThread {
                activity.triggerQuickRecordInWeb()
            }
        }

        @JavascriptInterface
        fun isAccessibilityServiceEnabled(): Boolean {
            return SingWalletAccessibilityService.isServiceRunning() ||
                   SingWalletAccessibilityService.checkAccessibilityEnabled(activity)
        }

        @JavascriptInterface
        fun openAccessibilitySettings() {
            activity.runOnUiThread {
                try {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    activity.startActivity(intent)
                    Toast.makeText(activity, "请找到「SingWallet 闪电记账」，开启无障碍快捷抓屏服务", Toast.LENGTH_LONG).show()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open accessibility settings: ${e.message}", e)
                    Toast.makeText(activity, "无法打开系统设置，请手动开启无障碍快捷抓屏服务", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}
