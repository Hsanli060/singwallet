package com.singwallet.app

import android.annotation.SuppressLint
import android.app.Activity
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
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.singwallet.app.services.QuickRecordTileService
import com.singwallet.app.services.SingWalletAccessibilityService
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * SingWallet 混合离线主宿主 Activity.
 *
 * 核心设计：
 * 1. 100% 像素级还原浏览器预览效果 (通过 file:///android_asset/index.html 离线渲染).
 * 2. 硬件加速 + 沉浸式暗黑主题 (#020617)，零闪屏零网络依赖秒级启动.
 * 3. 严格仅保留两个触发入口：
 *    - 入口一：下拉控制中心「闪电记账」磁贴 (QuickRecordTileService + SingWalletAccessibilityService).
 *    - 入口二：App 内「加一笔」按钮手动输入或主动选择一张账单图片上传.
 *    - 已彻底移除背部轻敲截屏监听与自动读取相册图片逻辑，无需申请任何相册/存储权限.
 * 4. 双擎 OTA 更新系统：免重装 Web 资源秒级热更新 + 全量 APK 覆盖升级.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "SingWalletActivity"
        private const val ASSET_ENTRY_URL = "file:///android_asset/index.html"
        private const val PREFS_OTA = "singwallet_ota_prefs"
        private const val KEY_SEEDED_APK_VERSION_CODE = "seeded_apk_version_code"
        private const val KEY_HOT_VERSION = "hot_version"
        private const val KEY_HOT_COMMIT_SHA = "hot_commit_sha"
        private const val KEY_HOT_UPDATED_AT = "hot_updated_at"
        private const val DEFAULT_REPO = "Hsanli060/singwallet"
        private const val DEFAULT_BRANCH = "master"

        private val WEB_BUNDLE_FILES = listOf(
            "index.html",
            "css/preview.css",
            "js/domain_config.js",
            "js/icon_registry.js",
            "js/dropdown_engine.js",
            "js/ocr_vlm_engine.js",
            "js/app_controller.js",
            "js/tailwindcss.min.js"
        )

        private val HOT_MUTABLE_FILES = listOf(
            "index.html",
            "css/preview.css",
            "js/domain_config.js",
            "js/icon_registry.js",
            "js/dropdown_engine.js",
            "js/ocr_vlm_engine.js",
            "js/app_controller.js"
        )

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
    private val otaExecutor: ExecutorService = Executors.newSingleThreadExecutor()
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
            val uris = mutableListOf<Uri>()
            val data = result.data
            if (result.resultCode == Activity.RESULT_OK && data != null) {
                val clipData = data.clipData
                if (clipData != null) {
                    for (i in 0 until clipData.itemCount) {
                        clipData.getItemAt(i)?.uri?.let { uri ->
                            if (!uris.contains(uri)) {
                                uris.add(uri)
                            }
                        }
                    }
                }
                data.data?.let { uri ->
                    if (!uris.contains(uri)) {
                        uris.add(uri)
                    }
                }
            }
            val finalResults = if (uris.isNotEmpty()) {
                uris.toTypedArray()
            } else {
                WebChromeClient.FileChooserParams.parseResult(result.resultCode, data)
            }
            filePathCallback?.onReceiveValue(finalResults)
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

            // 2. 初始化/种子化离线热更资源目录
            ensureWebHotBundleInitialized()

            // 3. 创建并配置硬件加速全屏 WebView
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

            // 4. 注册返回手势/物理按键拦截 (优先关闭 H5 内置弹窗)
            setupBackPressHandler(wv)

            // 5. 处理可能带入的启动 Intent (控制中心闪电记账快捷磁贴 / USB 实时热重载 dev_url)
            handleIntent(intent, isFromCreate = true)

            // 6. 扫描未处理的离线闪电抓屏任务
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

    fun getApkVersionCode(): Long {
        return try {
            val pInfo = packageManager.getPackageInfo(packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                pInfo.versionCode.toLong()
            }
        } catch (_: Exception) {
            1L
        }
    }

    fun getAppVersion(): String {
        return try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.8"
        } catch (_: Exception) {
            "1.0.8"
        }
    }

    /**
     * 初始化/种子化离线热更资源目录：
     * 每次 APK 覆盖安装（versionCode 升级）或 web_hot_bundle 缺失时，完整同步 assets 中的最新静态资源作为基线
     */
    private fun ensureWebHotBundleInitialized() {
        try {
            val prefs = getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
            val seededVersion = prefs.getLong(KEY_SEEDED_APK_VERSION_CODE, -1L)
            val currentVersionCode = getApkVersionCode()
            val hotEntryFile = File(filesDir, "web_hot_bundle/index.html")

            if (currentVersionCode > seededVersion || !hotEntryFile.exists() || hotEntryFile.length() == 0L) {
                Log.i(TAG, "Initializing/updating web_hot_bundle from APK assets (seeded=$seededVersion, current=$currentVersionCode)")
                val copied = copyAssetsToWebHotBundle()
                if (copied) {
                    prefs.edit()
                        .putLong(KEY_SEEDED_APK_VERSION_CODE, currentVersionCode)
                        .putString(KEY_HOT_COMMIT_SHA, "")
                        .putString(KEY_HOT_VERSION, "")
                        .putLong(KEY_HOT_UPDATED_AT, 0L)
                        .apply()
                    Log.i(TAG, "web_hot_bundle seeded successfully for versionCode $currentVersionCode")
                } else {
                    Log.w(TAG, "Failed to copy built-in assets to web_hot_bundle")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "ensureWebHotBundleInitialized error: ${e.message}", e)
        }
    }

    /**
     * 将 APK 内置 assets 中的核心前端资源写入 web_hot_bundle 目录
     */
    private fun copyAssetsToWebHotBundle(): Boolean {
        val hotBundleDir = File(filesDir, "web_hot_bundle")
        if (!hotBundleDir.exists()) {
            hotBundleDir.mkdirs()
        }
        return try {
            for (relPath in WEB_BUNDLE_FILES) {
                val destFile = File(hotBundleDir, relPath)
                destFile.parentFile?.mkdirs()
                assets.open(relPath).use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "copyAssetsToWebHotBundle failed: ${e.message}", e)
            false
        }
    }

    /**
     * 计算并解析当前应加载的 WebView 入口 URL：
     * 1. 优先使用本地网络热重载 dev_url (如 127.0.0.1).
     * 2. 否则如果 web_hot_bundle/index.html 存在，使用热更资源文件.
     * 3. 兜底回退至 file:///android_asset/index.html.
     */
    fun resolveEntryUrl(intent: Intent?): String {
        val devUrlExtra = intent?.getStringExtra("dev_url")
        val resetDev = intent?.getBooleanExtra("reset_dev", false) == true || devUrlExtra.equals("off", ignoreCase = true)
        if (!resetDev && isAllowedLoopbackDevUrl(devUrlExtra)) {
            return devUrlExtra!!
        }
        if (activeDevUrl != null && !resetDev && isAllowedLoopbackDevUrl(activeDevUrl)) {
            return activeDevUrl!!
        }
        val hotEntryFile = File(filesDir, "web_hot_bundle/index.html")
        if (hotEntryFile.exists() && hotEntryFile.length() > 0L) {
            return Uri.fromFile(hotEntryFile).toString()
        }
        return ASSET_ENTRY_URL
    }

    /**
     * 向 WebView 派发 OTA 进度回调
     */
    fun dispatchOtaProgress(
        percent: Int,
        status: String,
        done: Boolean,
        error: String? = null,
        version: String = "",
        commitSha: String = ""
    ) {
        mainHandler.post {
            try {
                val payload = JSONObject().apply {
                    put("percent", percent)
                    put("status", status)
                    put("done", done)
                    if (error != null) {
                        put("error", error)
                    } else {
                        put("error", JSONObject.NULL)
                    }
                    put("version", version)
                    put("commitSha", commitSha)
                }.toString()
                val script = """
                    if (typeof window.onNativeOtaProgress === 'function') {
                        window.onNativeOtaProgress($payload);
                    }
                """.trimIndent()
                webView?.evaluateJavascript(script, null)
            } catch (e: Exception) {
                Log.w(TAG, "dispatchOtaProgress error: ${e.message}")
            }
        }
    }

    /**
     * 通用 HTTP/HTTPS 下载工具，带 30x 重定向自动跟踪与进度回调
     */
    private fun downloadUrlToFile(
        urlStr: String,
        destFile: File,
        authToken: String? = null,
        onProgress: ((downloaded: Long, total: Long) -> Unit)? = null
    ) {
        var curUrl = urlStr
        var redirects = 0
        while (redirects < 5) {
            val url = URL(curUrl)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 10000
                readTimeout = 25000
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "SingWallet-OTA/${getAppVersion()} Mobile")
                if (curUrl.contains("api.github.com")) {
                    setRequestProperty("Accept", "application/vnd.github.v3.raw")
                } else {
                    setRequestProperty("Accept", "*/*")
                }
                val isS3Presigned = curUrl.contains("amazonaws.com") || curUrl.contains("X-Amz-")
                val cleanToken = authToken?.trim()?.removePrefix("token ")?.removePrefix("Bearer ")?.trim()
                if (!cleanToken.isNullOrEmpty() && !isS3Presigned) {
                    setRequestProperty("Authorization", "token $cleanToken")
                }
            }
            val responseCode = conn.responseCode
            if (responseCode in 301..308) {
                val location = conn.getHeaderField("Location")
                conn.disconnect()
                if (location != null) {
                    curUrl = if (location.startsWith("http://") || location.startsWith("https://")) {
                        location
                    } else {
                        URL(url, location).toString()
                    }
                    redirects++
                    continue
                }
            }
            if (responseCode !in 200..299) {
                conn.disconnect()
                throw IOException("HTTP $responseCode from $curUrl")
            }
            val totalLength = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                conn.contentLengthLong
            } else {
                conn.contentLength.toLong()
            }
            conn.inputStream.use { input ->
                destFile.parentFile?.mkdirs()
                FileOutputStream(destFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalBytesRead = 0L
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead
                        onProgress?.invoke(totalBytesRead, totalLength)
                    }
                    output.flush()
                }
            }
            conn.disconnect()
            return
        }
        throw IOException("Too many redirects: $curUrl")
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
        settings.userAgentString = "$defaultUa SingWalletAndroid/1.0.8 Mobile"

        wv.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")

        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                if (url.startsWith("file://") ||
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

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                val url = request?.url?.toString() ?: return super.shouldInterceptRequest(view, request)
                if (url.startsWith("file:///android_asset/")) {
                    val cleanUrl = url.substringBefore('?').substringBefore('#')
                    val relPath = cleanUrl.removePrefix("file:///android_asset/")
                    val hotFile = File(filesDir, "web_hot_bundle/$relPath")
                    if (hotFile.exists() && hotFile.isFile && hotFile.canRead()) {
                        val mimeType = when {
                            relPath.endsWith(".html", ignoreCase = true) -> "text/html"
                            relPath.endsWith(".css", ignoreCase = true) -> "text/css"
                            relPath.endsWith(".js", ignoreCase = true) -> "application/javascript"
                            relPath.endsWith(".json", ignoreCase = true) -> "application/json"
                            relPath.endsWith(".png", ignoreCase = true) -> "image/png"
                            relPath.endsWith(".jpg", ignoreCase = true) || relPath.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
                            relPath.endsWith(".svg", ignoreCase = true) -> "image/svg+xml"
                            else -> "application/octet-stream"
                        }
                        try {
                            return WebResourceResponse(mimeType, "UTF-8", FileInputStream(hotFile))
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed reading hot file $relPath: ${e.message}")
                        }
                    }
                }
                return super.shouldInterceptRequest(view, request)
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
                    view?.loadUrl(resolveEntryUrl(null))
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

                val isMultiple = fileChooserParams?.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE ||
                    fileChooserParams?.acceptTypes?.any { it.contains("image") } == true
                val acceptTypes = fileChooserParams?.acceptTypes?.filter { it.isNotBlank() } ?: emptyList()
                val isImagePick = acceptTypes.isEmpty() || acceptTypes.any { it.contains("image", ignoreCase = true) }

                fun createGetContentIntent(): Intent {
                    return Intent(Intent.ACTION_GET_CONTENT).apply {
                        if (isImagePick) {
                            type = "image/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        } else {
                            type = acceptTypes.firstOrNull() ?: "*/*"
                            if (isMultiple) {
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            }
                        }
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                }

                try {
                    if (isImagePick && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        try {
                            val maxImages = try {
                                MediaStore.getPickImagesMaxLimit().coerceAtMost(50)
                            } catch (_: Throwable) {
                                20
                            }
                            val intent = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                                type = "image/*"
                                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maxImages)
                            }
                            fileChooserLauncher.launch(intent)
                            return true
                        } catch (tiramisuEx: Throwable) {
                            Log.w(TAG, "MediaStore.ACTION_PICK_IMAGES launch failed, fallback to ACTION_GET_CONTENT: ${tiramisuEx.message}")
                            val fallbackIntent = createGetContentIntent()
                            fileChooserLauncher.launch(fallbackIntent)
                            return true
                        }
                    } else {
                        val intent = createGetContentIntent()
                        fileChooserLauncher.launch(intent)
                        return true
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to launch file chooser: ${e.message}", e)
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
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
                    File(filesDir, "pending_lightning_captures")
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
                webView?.loadUrl(resolveEntryUrl(null))
            }
            return
        }

        // 1. USB 实时热重载 dev_url 切换与重置回退
        val devUrlExtra = intent.getStringExtra("dev_url")
        val resetDev = intent.getBooleanExtra("reset_dev", false) || devUrlExtra.equals("off", ignoreCase = true)

        if (resetDev) {
            activeDevUrl = null
            webView?.settings?.cacheMode = WebSettings.LOAD_DEFAULT
            webView?.loadUrl(resolveEntryUrl(null))
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
            // 冷启动且未指定 dev_url 时，默认加载热更或内置离线页面
            webView?.loadUrl(resolveEntryUrl(intent))
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
        otaExecutor.shutdownNow()
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
            return activity.getAppVersion()
        }

        @JavascriptInterface
        fun isNativeApp(): Boolean {
            return true
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

        // ==========================================
        //  双擎 OTA 更新系统 JavaScriptInterface 接口
        // ==========================================

        /**
         * 获取当前原生宿主与 Web 热更元数据信息
         */
        @JavascriptInterface
        fun getHotUpdateInfo(): String {
            val prefs = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
            return JSONObject().apply {
                put("apkVersion", activity.getAppVersion())
                put("apkVersionCode", activity.getApkVersionCode())
                put("hotVersion", prefs.getString(KEY_HOT_VERSION, "") ?: "")
                put("hotCommitSha", prefs.getString(KEY_HOT_COMMIT_SHA, "") ?: "")
                put("hotUpdatedAt", prefs.getLong(KEY_HOT_UPDATED_AT, 0L))
                put("repo", DEFAULT_REPO)
            }.toString()
        }

        /**
         * 执行免重装 Web 资源秒级热更新：
         * 从 GitHub / CDN 镜像拉取最新核心前端文件至 web_hot_bundle，校验后秒级原地刷新
         */
        @JavascriptInterface
        fun performWebHotUpdate(configJson: String) {
            activity.otaExecutor.execute {
                val config = try {
                    if (configJson.isNotBlank()) JSONObject(configJson) else JSONObject()
                } catch (_: Exception) {
                    JSONObject()
                }
                val repo = config.optString("repo", DEFAULT_REPO).ifBlank { DEFAULT_REPO }
                val branch = config.optString("branch", DEFAULT_BRANCH).ifBlank { DEFAULT_BRANCH }
                val version = config.optString("version", "")
                val commitSha = config.optString("commitSha", "").trim()
                val targetRef = if (commitSha.isNotEmpty()) commitSha else branch
                val tokenFromPrefs = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE).getString("github_token", "") ?: ""
                val token = config.optString("token", "").trim().ifBlank { tokenFromPrefs }
                if (token.isNotEmpty()) {
                    activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE).edit().putString("github_token", token).apply()
                }

                val stagingDir = File(activity.filesDir, "web_hot_staging")
                try {
                    stagingDir.deleteRecursively()
                    stagingDir.mkdirs()

                    activity.dispatchOtaProgress(5, "开始检查并下载热更资源...", false, null, version, commitSha)

                    val totalFiles = HOT_MUTABLE_FILES.size
                    for ((index, relPath) in HOT_MUTABLE_FILES.withIndex()) {
                        val stagingFile = File(stagingDir, relPath)
                        stagingFile.parentFile?.mkdirs()

                        val remotePath = "web/$relPath"
                        val candidateUrls = if (token.isNotEmpty()) {
                            listOf(
                                "https://raw.githubusercontent.com/$repo/$targetRef/$remotePath",
                                "https://api.github.com/repos/$repo/contents/$remotePath?ref=$targetRef",
                                "https://cdn.jsdelivr.net/gh/$repo@$targetRef/$remotePath?t=${System.currentTimeMillis()}",
                                "https://ghfast.top/https://raw.githubusercontent.com/$repo/$targetRef/$remotePath"
                            )
                        } else {
                            listOf(
                                "https://cdn.jsdelivr.net/gh/$repo@$targetRef/$remotePath?t=${System.currentTimeMillis()}",
                                "https://ghfast.top/https://raw.githubusercontent.com/$repo/$targetRef/$remotePath",
                                "https://raw.githubusercontent.com/$repo/$targetRef/$remotePath"
                            )
                        }

                        var fileDownloaded = false
                        var lastErr: Throwable? = null

                        for (urlStr in candidateUrls) {
                            try {
                                activity.downloadUrlToFile(urlStr, stagingFile, token.ifBlank { null })
                                if (!stagingFile.exists() || stagingFile.length() == 0L) {
                                    stagingFile.delete()
                                    continue
                                }
                                if (relPath == "index.html") {
                                    val content = stagingFile.readText(Charsets.UTF_8)
                                    if (!content.contains("<html", ignoreCase = true)) {
                                        stagingFile.delete()
                                        throw IllegalStateException("index.html 校验失败: 缺少 <html 标签")
                                    }
                                }
                                fileDownloaded = true
                                break
                            } catch (t: Throwable) {
                                lastErr = t
                                Log.w(TAG, "Download attempt failed for $relPath ($urlStr): ${t.message}")
                                if (stagingFile.exists()) {
                                    stagingFile.delete()
                                }
                            }
                        }

                        if (!fileDownloaded || !stagingFile.exists()) {
                            throw IllegalStateException("文件 $relPath 下载失败 (所有镜像源均不可用): ${lastErr?.message}")
                        }

                        val percent = 10 + ((index + 1) * 80 / totalFiles)
                        activity.dispatchOtaProgress(
                            percent,
                            "已更新组件 (${index + 1}/$totalFiles): ${relPath.substringAfterLast('/')}",
                            false,
                            null,
                            version,
                            commitSha
                        )
                    }

                    // 保留不变的三方库 tailwindcss.min.js
                    val tailwindStaging = File(stagingDir, "js/tailwindcss.min.js")
                    tailwindStaging.parentFile?.mkdirs()
                    val tailwindExisting = File(activity.filesDir, "web_hot_bundle/js/tailwindcss.min.js")
                    if (tailwindExisting.exists() && tailwindExisting.length() > 0L) {
                        tailwindExisting.copyTo(tailwindStaging, overwrite = true)
                    } else {
                        activity.assets.open("js/tailwindcss.min.js").use { input ->
                            FileOutputStream(tailwindStaging).use { output ->
                                input.copyTo(output)
                            }
                        }
                    }

                    // 全部文件校验完毕，覆盖拷贝到 web_hot_bundle
                    val hotBundleDir = File(activity.filesDir, "web_hot_bundle").apply { mkdirs() }
                    stagingDir.walkTopDown().forEach { file ->
                        if (file.isFile) {
                            val rel = file.relativeTo(stagingDir).path
                            val target = File(hotBundleDir, rel)
                            target.parentFile?.mkdirs()
                            file.copyTo(target, overwrite = true)
                        }
                    }

                    // 记录热更版本信息
                    val prefs = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
                    prefs.edit()
                        .putString(KEY_HOT_VERSION, version)
                        .putString(KEY_HOT_COMMIT_SHA, commitSha)
                        .putLong(KEY_HOT_UPDATED_AT, System.currentTimeMillis())
                        .apply()

                    activity.dispatchOtaProgress(100, "热更完成，正在重新加载页面...", true, null, version, commitSha)

                    // 延迟 400ms 清理缓存并刷新 WebView
                    activity.mainHandler.postDelayed({
                        try {
                            activity.webView?.clearCache(true)
                            activity.webView?.loadUrl(activity.resolveEntryUrl(activity.intent))
                            Toast.makeText(activity, "热更新已生效！", Toast.LENGTH_SHORT).show()
                        } catch (e: Exception) {
                            Log.e(TAG, "WebView reload error: ${e.message}", e)
                        }
                    }, 400L)
                } catch (e: Throwable) {
                    Log.e(TAG, "performWebHotUpdate error: ${e.message}", e)
                    activity.dispatchOtaProgress(0, "热更新失败: ${e.message}", true, e.message, version, commitSha)
                } finally {
                    try {
                        stagingDir.deleteRecursively()
                    } catch (_: Throwable) {}
                }
            }
        }

        /**
         * 全量 APK 应用内后台多源加速下载并校验 SHA-256，通过 FileProvider 调起系统安装器
         */
        @JavascriptInterface
        fun downloadAndInstallApk(apkUrl: String, expectedSha256: String?) {
            activity.otaExecutor.execute {
                val otaDir = File(activity.cacheDir, "ota_apk").apply { mkdirs() }
                val apkFile = File(otaDir, "singwallet-update.apk")
                if (apkFile.exists()) {
                    apkFile.delete()
                }

                val candidateUrls = mutableListOf<String>()
                candidateUrls.add(apkUrl)
                if (apkUrl.contains("github.com") && !apkUrl.startsWith("https://ghfast.top/")) {
                    candidateUrls.add("https://ghfast.top/$apkUrl")
                }

                var downloaded = false
                var lastErr: Throwable? = null

                for (targetUrl in candidateUrls) {
                    try {
                        Log.i(TAG, "Attempting APK download from: $targetUrl")
                        activity.dispatchOtaProgress(0, "正在连接下载节点...", false, null)
                        var lastPercent = -1
                        var lastTime = 0L

                        val savedToken = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE).getString("github_token", null)
                        activity.downloadUrlToFile(targetUrl, apkFile, savedToken) { curBytes, totalBytes ->
                            if (totalBytes > 0) {
                                val pct = ((curBytes * 100) / totalBytes).toInt().coerceIn(0, 99)
                                val now = System.currentTimeMillis()
                                if (pct != lastPercent && (now - lastTime > 250 || pct == 99)) {
                                    lastPercent = pct
                                    lastTime = now
                                    activity.dispatchOtaProgress(pct, "正在下载新版本安装包 ($pct%)...", false, null)
                                }
                            }
                        }

                        if (apkFile.exists() && apkFile.length() > 1024L) {
                            downloaded = true
                            break
                        } else {
                            apkFile.delete()
                        }
                    } catch (t: Throwable) {
                        lastErr = t
                        Log.w(TAG, "Failed to download APK from $targetUrl: ${t.message}")
                        if (apkFile.exists()) apkFile.delete()
                    }
                }

                if (!downloaded || !apkFile.exists()) {
                    val msg = lastErr?.message ?: "安装包下载失败"
                    activity.dispatchOtaProgress(0, "下载失败: $msg", true, msg)
                    return@execute
                }

                // SHA-256 完整性校验
                if (!expectedSha256.isNullOrBlank()) {
                    activity.dispatchOtaProgress(99, "正在校验安装包完整性...", false, null)
                    val digest = MessageDigest.getInstance("SHA-256")
                    apkFile.inputStream().use { input ->
                        val buf = ByteArray(8192)
                        var len: Int
                        while (input.read(buf).also { len = it } != -1) {
                            digest.update(buf, 0, len)
                        }
                    }
                    val actualSha256 = digest.digest().joinToString("") { "%02x".format(it) }
                    if (!actualSha256.equals(expectedSha256.trim(), ignoreCase = true)) {
                        apkFile.delete()
                        val errMsg = "SHA-256 校验不匹配 (预期: $expectedSha256, 实际: $actualSha256)"
                        Log.e(TAG, errMsg)
                        activity.dispatchOtaProgress(0, errMsg, true, errMsg)
                        return@execute
                    }
                }

                activity.dispatchOtaProgress(100, "安装包下载完成，正在调起系统安装...", true, null)

                activity.mainHandler.post {
                    try {
                        val apkUri = FileProvider.getUriForFile(
                            activity,
                            "${activity.packageName}.fileprovider",
                            apkFile
                        )
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        activity.startActivity(installIntent)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start install activity: ${e.message}", e)
                        Toast.makeText(activity, "调起安装器失败: ${e.message}", Toast.LENGTH_LONG).show()
                        activity.dispatchOtaProgress(100, "调起安装器失败: ${e.message}", true, e.message)
                    }
                }
            }
        }

        /**
         * 热更一键安全回退：从 APK 内置 assets 重新覆盖至 web_hot_bundle 并刷新界面
         */
        @JavascriptInterface
        fun rollbackWebHotUpdate(): Boolean {
            return try {
                val success = activity.copyAssetsToWebHotBundle()
                if (success) {
                    val prefs = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
                    prefs.edit()
                        .putString(KEY_HOT_COMMIT_SHA, "")
                        .putString(KEY_HOT_VERSION, "")
                        .putLong(KEY_HOT_UPDATED_AT, System.currentTimeMillis())
                        .apply()
                    activity.mainHandler.post {
                        activity.webView?.clearCache(true)
                        activity.webView?.loadUrl(activity.resolveEntryUrl(activity.intent))
                        Toast.makeText(activity, "已恢复内置出厂版本", Toast.LENGTH_SHORT).show()
                    }
                }
                success
            } catch (e: Exception) {
                Log.e(TAG, "rollbackWebHotUpdate failed: ${e.message}", e)
                false
            }
        }
    }
}
