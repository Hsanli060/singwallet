package com.singwallet.app

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.provider.Settings
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
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import com.singwallet.app.services.QuickRecordTileService
import com.singwallet.app.services.SingWalletAccessibilityService
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * SingWallet 混合离线主宿主 Activity.
 *
 * 核心设计：
 * 1. 100% 像素级还原浏览器预览效果 (通过 file:///android_asset/singwallet_preview.html 离线渲染).
 * 2. 硬件加速 + 沉浸式暗黑主题 (#020617)，零闪屏零网络依赖秒级启动.
 * 3. 严格仅保留两个触发入口：
 *    - 入口一：下拉控制中心「闪电记账」磁贴 (QuickRecordTileService + SingWalletAccessibilityService).
 *    - 入口二：App 内「加一笔」按钮手动输入或主动选择一张账单图片上传.
 * 4. 已彻底移除背部轻敲截屏监听与自动读取相册图片逻辑，无需申请任何相册/存储权限.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "SingWalletActivity"
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
            val fileName = "lightning_${System.currentTimeMillis()}.jpg"
            val isQuickTile = source == "lightning-tile"
            if (act != null) {
                act.mainHandler.post {
                    if (act.isPageLoaded) {
                        act.dispatchScreenshotToWebView(dataUrl, fileName, isQuickTile)
                    } else {
                        synchronized(act.pendingScreenshots) {
                            act.pendingScreenshots.add(Triple(dataUrl, fileName, isQuickTile))
                        }
                    }
                }
            } else {
                Log.i(TAG, "MainActivity is not in memory; snapshot preserved in disk queue")
            }
        }
    }

    private var webView: WebView? = null
    private var isPageLoaded = false
    private var pendingTileTrigger = false
    private val pendingScreenshots = mutableListOf<Triple<String, String, Boolean>>() // (base64Image, fileName, isQuickTile)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ingestionExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var activeDevUrl: String? = null

    /**
     * 安全回环开发地址白名单校验：仅放行 127.0.0.1 与 localhost 本地回环地址，严防恶意外部 Intent 注入公网 URL
     */
    private fun isAllowedLoopbackDevUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return url.startsWith("http://127.0.0.1:") ||
               url.startsWith("http://127.0.0.1/") ||
               url.startsWith("http://localhost:") ||
               url.startsWith("http://localhost/")
    }

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

        // 注册全局异常捕获，确保即使有任何极端异常也能输出 Logcat，绝不静默闪退
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

            // 4. 处理可能带入的启动 Intent (控制中心闪电记账快捷磁贴 / USB 实时热重载 dev_url)
            handleIntent(intent, isFromCreate = true)

            // 5. 扫描未处理的离线闪电抓屏任务
            scanPendingLightningCaptures()
        } catch (t: Throwable) {
            Log.e(TAG, "Error in onCreate: ${t.message}", t)
        }
    }

    private fun applyWindowDecorations() {
        try {
            val darkBg = Color.parseColor("#020617")
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            @Suppress("DEPRECATION")
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
            @Suppress("DEPRECATION")
            window.statusBarColor = darkBg
            @Suppress("DEPRECATION")
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
        // 开启 Chrome DevTools 真机远程审查 (chrome://inspect/#devices)
        try {
            WebView.setWebContentsDebuggingEnabled(true)
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to enable WebContentsDebugging: ${e.message}")
        }

        val settings = wv.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        @Suppress("DEPRECATION")
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
        settings.userAgentString = "$defaultUa SingWalletAndroid/1.0.5 Mobile"

        wv.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")

        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                if (url.startsWith("file:///android_asset/") ||
                    url.startsWith("data:") ||
                    url.startsWith("blob:") ||
                    isAllowedLoopbackDevUrl(url)
                ) {
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

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                val failedUrl = request?.url?.toString()
                val isMainFrame = request?.isForMainFrame == true
                Log.w(TAG, "onReceivedError: url=$failedUrl, isMainFrame=$isMainFrame, errorCode=${error?.errorCode}, desc=${error?.description}")

                // 拔掉数据线或本地热重载开发服务未启动时的「零白屏自动离线兜底」
                if (isMainFrame && isAllowedLoopbackDevUrl(failedUrl)) {
                    Log.w(TAG, "Dev server unreachable, auto-falling back to built-in offline assets")
                    activeDevUrl = null
                    view?.settings?.cacheMode = WebSettings.LOAD_DEFAULT
                    view?.loadUrl(ASSET_ENTRY_URL)
                    Toast.makeText(this@MainActivity, "开发服务未连接，已自动切回内置离线版", Toast.LENGTH_SHORT).show()
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                Log.i(TAG, "SingWallet WebView loaded: $url")
                isPageLoaded = true

                // 注入 Native 模式标记 class
                wv.evaluateJavascript("document.body.classList.add('native-app');", null)

                // 刷新暂存的待处理闪电记账抓屏任务
                synchronized(pendingScreenshots) {
                    for ((base64Image, fileName, isQuickTile) in pendingScreenshots) {
                        dispatchScreenshotToWebView(base64Image, fileName, isQuickTile)
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
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
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
                            // 退至后台而不强制销毁，保持后台秒开与闪电记账能力
                            moveTaskToBack(true)
                        }
                    }
                }
            }
        })
    }

    private val scanLock = Any()

    /**
     * 扫描私有目录下尚未处理的闪电记账抓屏文件 (pending_lightning_captures / lightning_captures)
     */
    private fun scanPendingLightningCaptures() {
        if (ingestionExecutor.isShutdown) return
        ingestionExecutor.execute {
            synchronized(scanLock) {
                val candidateDirs = listOf(
                    File(filesDir, "pending_lightning_captures"),
                    File(filesDir, "lightning_captures")
                )
                for (dir in candidateDirs) {
                    try {
                        if (dir.exists() && dir.isDirectory) {
                            val files = dir.listFiles { f ->
                                f.extension.equals("jpg", ignoreCase = true) ||
                                f.extension.equals("jpeg", ignoreCase = true) ||
                                f.extension.equals("png", ignoreCase = true)
                            }
                            files?.sortBy { it.lastModified() }
                            files?.forEach { file ->
                                val originalName = file.name
                                // 原子认领机制：通过 renameTo 成为专属 processing 文件，杜绝与冷启动/热启动并发扫描重复处理
                                val processingFile = File(dir, "${file.nameWithoutExtension}_${System.currentTimeMillis()}.processing")
                                if (file.renameTo(processingFile)) {
                                    try {
                                        val bytes = processingFile.readBytes()
                                        val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                        val dataUrl = "data:image/jpeg;base64,$base64"
                                        mainHandler.post {
                                            if (isPageLoaded) {
                                                dispatchScreenshotToWebView(dataUrl, originalName, true)
                                            } else {
                                                synchronized(pendingScreenshots) {
                                                    pendingScreenshots.add(Triple(dataUrl, originalName, true))
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
                        Log.w(TAG, "scanPendingLightningCaptures error in ${dir.name}: ${e.message}")
                    }
                }
            }
        }
    }

    internal fun dispatchScreenshotToWebView(
        base64Image: String,
        fileName: String = "lightning_capture.jpg",
        isQuickTile: Boolean = true
    ) {
        val dataUrl = if (base64Image.startsWith("data:")) {
            base64Image
        } else {
            "data:image/jpeg;base64,$base64Image"
        }
        val source = if (isQuickTile) "lightning-tile" else "manual-upload"
        val escapedDataUrl = dataUrl.replace("\\", "\\\\").replace("'", "\\'")
        val escapedFileName = fileName.replace("\\", "\\\\").replace("'", "\\'")
        val script = """
            if (typeof window.onNativeScreenshotCaptured === 'function') {
                window.onNativeScreenshotCaptured('$escapedDataUrl', '$escapedFileName', $isQuickTile);
            } else if (typeof window.handleShortcutCapturedItem === 'function') {
                window.handleShortcutCapturedItem({
                    dataUrl: '$escapedDataUrl',
                    source: '$source',
                    fileName: '$escapedFileName',
                    uri: ''
                });
            }
        """.trimIndent()
        Log.i(TAG, "Dispatching lightning capture to WebView: fileName=$fileName, isQuickTile=$isQuickTile, len=${dataUrl.length}")
        webView?.evaluateJavascript(script) { result ->
            Log.i(TAG, "Lightning capture dispatched to WebView callback: evalResult=$result")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, isFromCreate = false)
    }

    private fun handleIntent(intent: Intent?, isFromCreate: Boolean = false) {
        if (intent == null) {
            if (isFromCreate && webView != null) {
                webView?.loadUrl(ASSET_ENTRY_URL)
            }
            return
        }

        // 1. USB 实时热重载 dev_url 切换与重置回退
        val devUrlExtra = intent.getStringExtra("dev_url")
        val resetDev = intent.getBooleanExtra("reset_dev", false) || devUrlExtra.equals("off", ignoreCase = true)

        if (resetDev) {
            activeDevUrl = null
            webView?.settings?.cacheMode = WebSettings.LOAD_DEFAULT
            webView?.loadUrl(ASSET_ENTRY_URL)
            Log.i(TAG, "Switched back to built-in offline assets")
            Toast.makeText(this, "已切回内置离线版", Toast.LENGTH_SHORT).show()
        } else if (isAllowedLoopbackDevUrl(devUrlExtra)) {
            activeDevUrl = devUrlExtra
            webView?.settings?.cacheMode = WebSettings.LOAD_NO_CACHE
            webView?.clearCache(true)
            webView?.loadUrl(devUrlExtra!!)
            Log.i(TAG, "Loading live hot-reload dev_url: $devUrlExtra")
            Toast.makeText(this, "已连接电脑 UI 实时热重载模式", Toast.LENGTH_SHORT).show()
        } else if (isFromCreate) {
            // 冷启动且未指定 dev_url 时，默认加载内置离线页面
            webView?.loadUrl(ASSET_ENTRY_URL)
        }

        // 2. 处理下拉控制中心「闪电记账」磁贴 Intent
        handleQuickRecordIntent(intent)
    }

    private fun handleQuickRecordIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val isQuickRecordTrigger = action == QuickRecordTileService.ACTION_TRIGGER_QUICK_RECORD ||
                                   intent.getBooleanExtra("quick_record_tile", false)
        if (isQuickRecordTrigger) {
            Log.i(TAG, "Received Quick Settings Tile Trigger")
            scanPendingLightningCaptures()
            if (isPageLoaded) {
                triggerQuickRecordInWeb()
            } else {
                pendingTileTrigger = true
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
                    @Suppress("DEPRECATION")
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
            // 相册监听已彻底移除，闪电记账在应用私有目录流转并自动清理，此处保留空实现兼容旧调用
            Log.d(TAG, "deleteScreenshot ignored (no-op in private lightning capture mode): $uriString")
        }

        @JavascriptInterface
        fun checkWatcherStatus(): String {
            val isA11yRunning = SingWalletAccessibilityService.getInstance() != null ||
                                SingWalletAccessibilityService.isServiceRunning() ||
                                SingWalletAccessibilityService.checkAccessibilityEnabled(activity)
            return JSONObject().apply {
                put("enabled", isA11yRunning)
                put("accessibilityEnabled", isA11yRunning)
                put("mode", "lightning-tile")
            }.toString()
        }

        @JavascriptInterface
        fun saveBackupFile(jsonContent: String, fileName: String): Boolean {
            val safeFileName = fileName.ifBlank { "singwallet_backup_${System.currentTimeMillis()}.json" }
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, safeFileName)
                        put(MediaStore.Downloads.MIME_TYPE, "application/json")
                        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val resolver = activity.contentResolver
                    val itemUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Failed to create MediaStore.Downloads entry")
                    resolver.openOutputStream(itemUri)?.use { out ->
                        out.write(jsonContent.toByteArray(Charsets.UTF_8))
                        out.flush()
                    } ?: throw IllegalStateException("Failed to open OutputStream for $itemUri")

                    val completeValues = ContentValues().apply {
                        put(MediaStore.Downloads.IS_PENDING, 0)
                    }
                    resolver.update(itemUri, completeValues, null, null)
                } else {
                    val downloadsDir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                        ?: File(activity.filesDir, "downloads")
                    if (!downloadsDir.exists()) {
                        downloadsDir.mkdirs()
                    }
                    val targetFile = File(downloadsDir, safeFileName)
                    FileOutputStream(targetFile).use { out ->
                        out.write(jsonContent.toByteArray(Charsets.UTF_8))
                        out.flush()
                    }
                }
                activity.runOnUiThread {
                    Toast.makeText(activity, "备份已保存至系统下载目录: $safeFileName", Toast.LENGTH_SHORT).show()
                }
                true
            } catch (e: Exception) {
                Log.e(TAG, "saveBackupFile failed: ${e.message}", e)
                activity.runOnUiThread {
                    Toast.makeText(activity, "保存备份文件失败: ${e.message}", Toast.LENGTH_SHORT).show()
                }
                false
            }
        }

        @JavascriptInterface
        fun getAppVersion(): String {
            return try {
                activity.packageManager.getPackageInfo(activity.packageName, 0).versionName ?: "1.0.5"
            } catch (_: Exception) {
                "1.0.5"
            }
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
