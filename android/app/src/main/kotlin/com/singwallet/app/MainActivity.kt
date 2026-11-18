package com.singwallet.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
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
import androidx.core.content.IntentCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.webkit.WebViewAssetLoader
import com.singwallet.app.data.SingWalletDatabaseHelper
import com.singwallet.app.security.SecureKeyStore
import com.singwallet.app.security.SwbkCryptoCodec
import com.singwallet.app.services.LightningAiBackgroundProcessor
import com.singwallet.app.services.LightningAiForegroundService
import com.singwallet.app.services.SingWalletAccessibilityService
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * SingWallet 混合离线主宿主 Activity.
 *
 * 核心安全与架构特性：
 * 1. 通过 WebViewAssetLoader 托管于 `https://appassets.androidplatform.net/assets/index.html`，
 *    全面禁用 file:// 跨源访问与全局明文流量。
 * 2. 硬件级 Keystore 加密密钥存储 + 原生 SWBK v1 加密备份 + 12 核心表 SQLite WAL 持久化。
 * 3. 双阶段 ACK 防丢单闪电队列、ACTION_SEND 系统分享截图直入解析、Android 15 Edge-to-Edge 安全区适配。
 * 4. 严格隔离 GitHub OTA Token 域名范围，强制热更 manifest 与 APK SHA-256 完整性校验。
 */
class MainActivity : ComponentActivity() {

    private class SingWalletUncaughtExceptionHandler(
        private val previousHandler: Thread.UncaughtExceptionHandler?
    ) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(thread: Thread, throwable: Throwable) {
            Log.e(TAG, "Uncaught exception on thread ${thread.name}: ${throwable.message}", throwable)
            previousHandler?.uncaughtException(thread, throwable)
        }
    }

    companion object {
        private const val TAG = "SingWalletActivity"
        private const val ASSET_ORIGIN = "https://appassets.androidplatform.net"
        private const val ASSET_ENTRY_URL = "$ASSET_ORIGIN/assets/index.html"
        private const val PREFS_OTA = "singwallet_ota_prefs"
        private const val KEY_SEEDED_APK_VERSION_CODE = "seeded_apk_version_code"
        private const val KEY_HOT_VERSION = "hot_version"
        private const val KEY_HOT_COMMIT_SHA = "hot_commit_sha"
        private const val KEY_HOT_UPDATED_AT = "hot_updated_at"
        private const val DEFAULT_REPO = "Hsanli060/singwallet"
        private const val DEFAULT_BRANCH = "master"

        private const val PROCESSING_RECOVERY_MS = 30_000L
        private const val ACK_PENDING_RECOVERY_MS = 120_000L
        private const val SHARE_TARGET_MAX_WIDTH = 1080

        private val REPO_REGEX = Regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
        private val REF_REGEX = Regex("^[A-Za-z0-9._/-]{1,100}$")
        private val SHA256_HEX_REGEX = Regex("^[0-9a-fA-F]{64}$")
        private val TOKEN_ALLOWED_HOSTS = setOf("api.github.com", "raw.githubusercontent.com")

        private val HOT_MUTABLE_FILES = listOf(
            "index.html",
            "favicon.svg",
            "css/preview.css",
            "css/tailwind.min.css",
            "js/domain_config.js",
            "js/icon_registry.js",
            "js/dropdown_engine.js",
            "js/ocr_vlm_engine.js",
            "js/storage_crypto_engine.js",
            "js/app_controller.js"
        )

        private val OPTIONAL_COMPAT_FILES = setOf(
            "css/tailwind.min.css",
            "js/storage_crypto_engine.js"
        )

        @Volatile
        private var instance: MainActivity? = null

        @Volatile
        private var isForeground: Boolean = false

        fun getInstance(): MainActivity? = instance

        fun isAlive(): Boolean = instance != null && !(instance?.isFinishing ?: true)

        fun isInForeground(): Boolean = isAlive() && isForeground

        fun notifyNativeParsingStarted(jpgFile: File, taskId: String) {
            val act = instance ?: return
            if (!isInForeground() || !act.isPageLoaded) return
            act.notifyNativeParsingStartedInternal(jpgFile, taskId)
        }

        fun onBackgroundParseCompleted(fileName: String) {
            val act = instance ?: return
            if (!isInForeground()) {
                Log.i(TAG, "Native background parse completed for $fileName while Activity is in background; deferred until onResume")
                return
            }
            Log.i(TAG, "Native background parse completed for $fileName, triggering immediate foreground ingestion")
            act.scanPendingLightningCaptures()
        }

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
    private var assetLoader: WebViewAssetLoader? = null
    private var isPageLoaded = false
    private var pendingTileTrigger = false
    private var safeTopDp = 0
    private var safeBottomDp = 0
    private val notifiedInFlightTasks = ConcurrentHashMap.newKeySet<String>()
    private val pendingScreenshots = mutableListOf<Triple<String, String, Boolean>>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ingestionExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val otaExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var activeDevUrl: String? = null
    private val scanLock = Any()

    private fun jsQuote(s: String): String {
        return JSONObject.quote(s)
            .replace("\u2028", "\\u2028")
            .replace("\u2029", "\\u2029")
    }

    private fun isAllowedLoopbackDevUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return try {
            val uri = Uri.parse(url.trim())
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            val host = uri.host?.lowercase(Locale.ROOT)
            scheme == "http" && host in setOf("127.0.0.1", "localhost")
        } catch (_: Exception) {
            false
        }
    }

    private fun isInternalAssetUrl(uri: Uri?): Boolean {
        if (uri == null) return false
        return uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals("appassets.androidplatform.net", ignoreCase = true)
    }

    private fun guessMimeType(relPath: String): String {
        return when {
            relPath.endsWith(".html", ignoreCase = true) -> "text/html"
            relPath.endsWith(".css", ignoreCase = true) -> "text/css"
            relPath.endsWith(".js", ignoreCase = true) -> "application/javascript"
            relPath.endsWith(".json", ignoreCase = true) -> "application/json"
            relPath.endsWith(".png", ignoreCase = true) -> "image/png"
            relPath.endsWith(".jpg", ignoreCase = true) || relPath.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
            relPath.endsWith(".webp", ignoreCase = true) -> "image/webp"
            relPath.endsWith(".svg", ignoreCase = true) -> "image/svg+xml"
            relPath.endsWith(".woff2", ignoreCase = true) -> "font/woff2"
            relPath.endsWith(".woff", ignoreCase = true) -> "font/woff"
            else -> "application/octet-stream"
        }
    }

    private fun buildWebViewAssetLoader(): WebViewAssetLoader {
        val builtInAssetsHandler = WebViewAssetLoader.AssetsPathHandler(this)
        val hotBundleDir = File(filesDir, "web_hot_bundle")
        val capturesDir = File(filesDir, "pending_lightning_captures")

        val assetsPathHandler = WebViewAssetLoader.PathHandler { rawPath ->
            val cleanRelPath = rawPath.substringBefore('?').substringBefore('#').trimStart('/')
            if (cleanRelPath.isEmpty()) {
                return@PathHandler builtInAssetsHandler.handle("index.html")
            }
            try {
                val hotRootCanonical = hotBundleDir.canonicalPath
                val candidate = File(hotBundleDir, cleanRelPath)
                val candidateCanonical = candidate.canonicalPath
                if (candidateCanonical.startsWith(hotRootCanonical + File.separator) &&
                    candidate.exists() && candidate.isFile && candidate.canRead()
                ) {
                    val mimeType = guessMimeType(cleanRelPath)
                    return@PathHandler WebResourceResponse(mimeType, "UTF-8", FileInputStream(candidate))
                }
            } catch (e: Exception) {
                Log.w(TAG, "Hot bundle asset lookup warning for $cleanRelPath: ${e.message}")
            }
            builtInAssetsHandler.handle(cleanRelPath)
        }

        val pendingCapturesHandler = WebViewAssetLoader.PathHandler { rawPath ->
            val cleanRelPath = rawPath.substringBefore('?').substringBefore('#').trimStart('/')
            if (cleanRelPath.isEmpty()) return@PathHandler null
            val lower = cleanRelPath.lowercase(Locale.ROOT)
            if (!lower.endsWith(".jpg") && !lower.endsWith(".jpeg") && !lower.endsWith(".png") && !lower.endsWith(".webp")) {
                return@PathHandler null
            }
            try {
                val capturesCanonical = capturesDir.canonicalPath
                val candidate = File(capturesDir, cleanRelPath)
                val candidateCanonical = candidate.canonicalPath
                if (candidateCanonical.startsWith(capturesCanonical + File.separator) &&
                    candidate.exists() && candidate.isFile && candidate.canRead()
                ) {
                    return@PathHandler WebResourceResponse(guessMimeType(cleanRelPath), null, FileInputStream(candidate))
                }
            } catch (e: Exception) {
                Log.w(TAG, "Pending capture read warning for $cleanRelPath: ${e.message}")
            }
            null
        }

        return WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", assetsPathHandler)
            .addPathHandler("/pending-captures/", pendingCapturesHandler)
            .build()
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
                            if (!uris.contains(uri)) uris.add(uri)
                        }
                    }
                }
                data.data?.let { uri ->
                    if (!uris.contains(uri)) uris.add(uri)
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

    private val backupFilePickerLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val uri = result.data?.data ?: result.data?.clipData?.getItemAt(0)?.uri
            if (uri != null && !ingestionExecutor.isShutdown) {
                ingestionExecutor.execute {
                    try {
                        val rawBytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        if (rawBytes == null || rawBytes.isEmpty()) {
                            throw IllegalStateException("所选文件为空")
                        }
                        val displayName = resolveDisplayName(uri)
                        val isSwbk = rawBytes.size >= 6 &&
                            rawBytes[0] == 'S'.code.toByte() &&
                            rawBytes[1] == 'W'.code.toByte() &&
                            rawBytes[2] == 'B'.code.toByte() &&
                            rawBytes[3] == 'K'.code.toByte() &&
                            rawBytes[4] == 0x00.toByte() &&
                            rawBytes[5] == 0x01.toByte()

                        if (isSwbk) {
                            val base64Str = Base64.encodeToString(rawBytes, Base64.NO_WRAP)
                            val script = """
                                if (typeof window.onNativeSwbkBackupSelected === 'function') {
                                    window.onNativeSwbkBackupSelected(${jsQuote(base64Str)}, ${jsQuote(displayName)});
                                }
                            """.trimIndent()
                            mainHandler.post {
                                webView?.evaluateJavascript(script, null)
                            }
                        } else {
                            val jsonContent = rawBytes.toString(Charsets.UTF_8).removePrefix("\uFEFF")
                            if (jsonContent.isNotBlank()) {
                                val script = """
                                    if (typeof window.importBackupFromJson === 'function') {
                                        window.importBackupFromJson(${jsQuote(jsonContent)});
                                    }
                                """.trimIndent()
                                mainHandler.post {
                                    webView?.evaluateJavascript(script, null)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to read picked backup file: ${e.message}", e)
                        mainHandler.post {
                            Toast.makeText(this@MainActivity, "读取备份文件失败: ${e.message}", Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }

    private fun resolveDisplayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)?.trim()
                    if (!name.isNullOrEmpty()) return name
                }
            }
        } catch (_: Exception) {}
        return uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { "singwallet_backup" } ?: "singwallet_backup"
    }

    fun launchBackupFilePicker() {
        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream", "*/*"))
                addCategory(Intent.CATEGORY_OPENABLE)
            }
            backupFilePickerLauncher.launch(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch backup file picker: ${e.message}", e)
            Toast.makeText(this, "调起文件选择器失败: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        isForeground = true

        // 安装全局未捕获异常处理器：保留系统默认处理器链，记录日志后正常传递，绝不吞掉崩溃
        val currentDefaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        if (currentDefaultHandler !is SingWalletUncaughtExceptionHandler) {
            Thread.setDefaultUncaughtExceptionHandler(SingWalletUncaughtExceptionHandler(currentDefaultHandler))
        }

        try {
            // 1. Edge-to-Edge 与沉浸式暗黑系统栏样式
            applyWindowDecorations()

            // 2. APK 升级时清理陈旧热更缓存，冷启动零阻塞直接由 WebViewAssetLoader 读取内置 assets
            cleanupStaleHotBundleOnUpgrade()

            // 3. 构建 WebViewAssetLoader
            assetLoader = buildWebViewAssetLoader()

            // 4. 创建根容器与硬件加速全屏 WebView
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

            setupEdgeToEdgeInsets(rootLayout)
            configureWebView(wv)
            setupBackPressHandler(wv)

            // 5. 处理启动 Intent (dev_url / ACTION_SEND 图片分享)
            handleIntent(intent, isFromCreate = true)

            // 6. 扫描未处理的离线闪电抓屏任务
            scanPendingLightningCaptures()
        } catch (t: Throwable) {
            Log.e(TAG, "Error in onCreate: ${t.message}", t)
        }
    }

    private fun applyWindowDecorations() {
        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val darkBg = Color.parseColor("#020617")
            @Suppress("DEPRECATION")
            window.statusBarColor = darkBg
            @Suppress("DEPRECATION")
            window.navigationBarColor = darkBg
            val controller = WindowInsetsControllerCompat(window, window.decorView)
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
        } catch (e: Throwable) {
            Log.w(TAG, "applyWindowDecorations warning: ${e.message}")
        }
    }

    private fun setupEdgeToEdgeInsets(rootLayout: FrameLayout) {
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, windowInsets ->
            val bars = windowInsets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime())
            view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))

            val density = resources.displayMetrics.density.coerceAtLeast(1f)
            safeTopDp = (bars.top / density).roundToInt()
            safeBottomDp = (bars.bottom / density).roundToInt()
            injectSafeAreaCssVars()
            WindowInsetsCompat.CONSUMED
        }
        ViewCompat.requestApplyInsets(rootLayout)
    }

    private fun injectSafeAreaCssVars() {
        val wv = webView ?: return
        if (!isPageLoaded) return
        // rootLayout 已应用安全区内边距，--safe-top / --safe-bottom 置 0px 避免重复留白，同时暴露真实 dp 元数据
        val script = """
            (function() {
                try {
                    document.documentElement.style.setProperty('--safe-top', '0px');
                    document.documentElement.style.setProperty('--safe-bottom', '0px');
                    window.__nativeSafeInsetsDp = { top: $safeTopDp, bottom: $safeBottomDp };
                } catch (e) {}
            })();
        """.trimIndent()
        wv.evaluateJavascript(script, null)
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
     * APK 版本变化时仅清理过期热更目录，直接通过 WebViewAssetLoader 按需读取内置 assets/
     */
    private fun cleanupStaleHotBundleOnUpgrade() {
        try {
            val prefs = getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
            val lastSyncedApkVersion = prefs.getLong(KEY_SEEDED_APK_VERSION_CODE, -1L)
            val currentVersionCode = getApkVersionCode()
            if (lastSyncedApkVersion != currentVersionCode) {
                val hotDir = File(filesDir, "web_hot_bundle")
                if (hotDir.exists()) {
                    hotDir.deleteRecursively()
                }
                prefs.edit()
                    .putLong(KEY_SEEDED_APK_VERSION_CODE, currentVersionCode)
                    .putString(KEY_HOT_COMMIT_SHA, "")
                    .putString(KEY_HOT_VERSION, "")
                    .putLong(KEY_HOT_UPDATED_AT, 0L)
                    .apply()
                Log.i(TAG, "Cleaned stale web_hot_bundle on APK version change ($lastSyncedApkVersion -> $currentVersionCode)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "cleanupStaleHotBundleOnUpgrade error: ${e.message}", e)
        }
    }

    fun resolveEntryUrl(intent: Intent?): String {
        val devUrlExtra = intent?.getStringExtra("dev_url")
        val resetDev = intent?.getBooleanExtra("reset_dev", false) == true || devUrlExtra.equals("off", ignoreCase = true)
        if (!resetDev && isAllowedLoopbackDevUrl(devUrlExtra)) {
            return devUrlExtra!!.trim()
        }
        if (activeDevUrl != null && !resetDev && isAllowedLoopbackDevUrl(activeDevUrl)) {
            return activeDevUrl!!
        }
        return ASSET_ENTRY_URL
    }

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
                    if (error != null) put("error", error) else put("error", JSONObject.NULL)
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
     * 安全 HTTPS 下载工具：
     * - 仅允许 HTTPS 协议
     * - 关闭自动重定向并手动逐跳校验
     * - 严格限制仅当目标为 https://api.github.com 或 https://raw.githubusercontent.com 时才携带 Token
     */
    private fun downloadUrlToFile(
        urlStr: String,
        destFile: File,
        authToken: String? = null,
        onProgress: ((downloaded: Long, total: Long) -> Unit)? = null
    ) {
        var curUrl = urlStr
        var redirects = 0
        val cleanToken = authToken?.trim()?.removePrefix("token ")?.removePrefix("Bearer ")?.trim()

        while (redirects < 5) {
            val url = URL(curUrl)
            if (!url.protocol.equals("https", ignoreCase = true)) {
                throw SecurityException("拒绝非 HTTPS 下载请求: ${url.protocol}")
            }
            val host = url.host.lowercase(Locale.ROOT)
            val allowTokenForHost = !cleanToken.isNullOrEmpty() && host in TOKEN_ALLOWED_HOSTS

            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 25_000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "SingWallet-OTA/${getAppVersion()} Mobile")
                if (host == "api.github.com") {
                    setRequestProperty("Accept", "application/vnd.github.v3.raw")
                } else {
                    setRequestProperty("Accept", "*/*")
                }
                if (allowTokenForHost) {
                    setRequestProperty("Authorization", "token $cleanToken")
                }
            }

            try {
                val responseCode = conn.responseCode
                if (responseCode in 301..308) {
                    val location = conn.getHeaderField("Location")
                        ?: throw IOException("Redirect $responseCode missing Location header")
                    curUrl = if (location.startsWith("http://", ignoreCase = true) ||
                        location.startsWith("https://", ignoreCase = true)
                    ) {
                        location
                    } else {
                        URL(url, location).toString()
                    }
                    redirects++
                    continue
                }
                if (responseCode !in 200..299) {
                    throw IOException("HTTP $responseCode from $host")
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
                return
            } finally {
                try {
                    conn.disconnect()
                } catch (_: Throwable) {}
            }
        }
        throw IOException("Too many redirects while downloading from $urlStr")
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(wv: WebView) {
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (isDebuggable) {
            try {
                WebView.setWebContentsDebuggingEnabled(true)
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to enable WebContentsDebugging: ${e.message}")
            }
        }

        val settings = wv.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        @Suppress("DEPRECATION")
        settings.databaseEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        @Suppress("DEPRECATION")
        settings.allowFileAccessFromFileURLs = false
        @Suppress("DEPRECATION")
        settings.allowUniversalAccessFromFileURLs = false
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.mediaPlaybackRequiresUserGesture = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.setSupportZoom(false)
        settings.builtInZoomControls = false
        settings.displayZoomControls = false

        val defaultUa = settings.userAgentString
        settings.userAgentString = "$defaultUa SingWalletAndroid/${getAppVersion()} Mobile"

        wv.addJavascriptInterface(AndroidBridge(this), "AndroidBridge")

        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return false
                val url = uri.toString()
                if (isInternalAssetUrl(uri) ||
                    url.startsWith("data:") ||
                    url.startsWith("blob:") ||
                    isAllowedLoopbackDevUrl(url)
                ) {
                    return false
                }
                val scheme = uri.scheme?.lowercase(Locale.ROOT)
                if (scheme == "http" || scheme == "https") {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                    } catch (e: Exception) {
                        Log.w(TAG, "Cannot launch external url: $url", e)
                    }
                } else {
                    Log.w(TAG, "Blocked untrusted URI scheme: $scheme")
                }
                return true
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                val uri = request?.url ?: return super.shouldInterceptRequest(view, request)
                val intercepted = assetLoader?.shouldInterceptRequest(uri)
                if (intercepted != null) {
                    return intercepted
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

                if (isMainFrame && isAllowedLoopbackDevUrl(failedUrl)) {
                    Log.w(TAG, "Dev server unreachable, auto-falling back to built-in offline assets")
                    activeDevUrl = null
                    view?.settings?.apply {
                        cacheMode = WebSettings.LOAD_DEFAULT
                        mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                    }
                    view?.loadUrl(resolveEntryUrl(null))
                    Toast.makeText(this@MainActivity, "开发服务未连接，已自动切回内置离线版", Toast.LENGTH_SHORT).show()
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                Log.i(TAG, "SingWallet WebView loaded: $url")
                isPageLoaded = true

                wv.evaluateJavascript("document.body.classList.add('native-app');", null)
                injectSafeAreaCssVars()

                val syncAiConfigScript = """
                    (function() {
                        try {
                            if (typeof window.syncAiConfigToNativeBridge === 'function') {
                                window.syncAiConfigToNativeBridge();
                            } else if (window.AndroidBridge && typeof window.AndroidBridge.syncAiConfigToNative === 'function') {
                                var rawCfg = localStorage.getItem('singwallet_vlm_config');
                                var cfg = rawCfg ? JSON.parse(rawCfg) : {};
                                var eng = localStorage.getItem('singwallet_ocr_engine') || 'llm';
                                var cats = (window.DomainRegistry && typeof window.DomainRegistry.getParentCategories === 'function')
                                    ? window.DomainRegistry.getParentCategories()
                                    : (window.CORE_PARENT_CATEGORIES || []);
                                window.AndroidBridge.syncAiConfigToNative(JSON.stringify({
                                    provider: cfg.provider || 'openai_chat',
                                    apiKey: cfg.apiKey || '',
                                    endpoint: cfg.endpoint || '',
                                    model: cfg.model || '',
                                    ocrEngine: eng,
                                    categories: cats,
                                    autoCommitEnabled: Boolean(window.autoCommitEnabled),
                                    autoCommitThreshold: Number(window.autoCommitThreshold || 95)
                                }));
                            }
                            return 'ok';
                        } catch (e) {
                            return 'err';
                        }
                    })();
                """.trimIndent()
                wv.evaluateJavascript(syncAiConfigScript) {
                    scanPendingLightningCaptures()
                }

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
                val isExplicitBackup = acceptTypes.any { it.contains("json", ignoreCase = true) }
                val isImagePick = !isExplicitBackup && (acceptTypes.isEmpty() || acceptTypes.any { it.contains("image", ignoreCase = true) })

                fun createGetContentIntent(): Intent {
                    return Intent(Intent.ACTION_GET_CONTENT).apply {
                        if (isImagePick) {
                            type = "image/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        } else if (isExplicitBackup) {
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream", "*/*"))
                        } else {
                            val rawType = acceptTypes.firstOrNull() ?: "*/*"
                            type = if (rawType.contains("/")) rawType else "*/*"
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
                            fileChooserLauncher.launch(createGetContentIntent())
                            return true
                        }
                    } else {
                        fileChooserLauncher.launch(createGetContentIntent())
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
                            moveTaskToBack(true)
                        }
                    }
                }
            }
        })
    }

    internal fun notifyNativeParsingStartedInternal(jpgFile: File, taskId: String) {
        if (ingestionExecutor.isShutdown) return
        if (!notifiedInFlightTasks.add(taskId)) return
        ingestionExecutor.execute {
            try {
                if (!jpgFile.exists()) return@execute
                val bytes = jpgFile.readBytes()
                val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                val dataUrl = "data:image/jpeg;base64,$base64"
                val script = """
                    if (typeof window.onNativeLightningParsingStarted === 'function') {
                        window.onNativeLightningParsingStarted(${jsQuote(taskId)}, ${jsQuote(dataUrl)}, ${jsQuote(jpgFile.name)});
                    }
                """.trimIndent()
                mainHandler.post {
                    if (isPageLoaded) {
                        webView?.evaluateJavascript(script, null)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "notifyNativeParsingStartedInternal error: ${e.message}")
            }
        }
    }

    /**
     * 恢复异常中断残留的 .processing (>30s) 与未 ACK 的 .ack_pending (>120s) 文件
     */
    private fun recoverOrphanPendingFilesLocked(dir: File, nowMs: Long) {
        dir.listFiles { f -> f.name.endsWith(".processing", ignoreCase = true) }?.forEach { procFile ->
            if (nowMs - procFile.lastModified() > PROCESSING_RECOVERY_MS) {
                if (procFile.name.endsWith(".img.processing")) {
                    val originalImgName = procFile.name.substringBeforeLast("__claim_")
                    if (originalImgName.isNotEmpty() && originalImgName != procFile.name) {
                        val restoredImg = File(dir, originalImgName)
                        if (!restoredImg.exists()) procFile.renameTo(restoredImg)
                    } else {
                        val basePrefix = procFile.name.removeSuffix(".img.processing").substringBeforeLast("_")
                        val restoredImg = File(dir, "$basePrefix.jpg")
                        if (!restoredImg.exists()) procFile.renameTo(restoredImg)
                    }
                } else if (procFile.name.endsWith(".parsed.processing")) {
                    val baseName = procFile.name.substringBeforeLast("__claim_")
                        .takeIf { it != procFile.name }
                        ?: procFile.name.removeSuffix(".parsed.processing").substringBeforeLast("_")
                    val restoredParsed = File(dir, "$baseName.parsed.json")
                    if (!restoredParsed.exists()) procFile.renameTo(restoredParsed)
                }
            }
        }

        dir.listFiles { f -> f.name.endsWith(".ack_pending", ignoreCase = true) }?.forEach { ackFile ->
            if (nowMs - ackFile.lastModified() > ACK_PENDING_RECOVERY_MS) {
                if (ackFile.name.endsWith(".img.ack_pending")) {
                    val origImgName = ackFile.name.removeSuffix(".img.ack_pending")
                    val restoredImg = File(dir, origImgName)
                    if (!restoredImg.exists()) ackFile.renameTo(restoredImg)
                } else if (ackFile.name.endsWith(".parsed.json.ack_pending")) {
                    val origParsedName = ackFile.name.removeSuffix(".ack_pending")
                    val restoredParsed = File(dir, origParsedName)
                    if (!restoredParsed.exists()) ackFile.renameTo(restoredParsed)
                }
            }
        }
    }

    private fun scanPendingLightningCaptures() {
        if (ingestionExecutor.isShutdown) return
        ingestionExecutor.execute {
            if (!isPageLoaded) return@execute
            synchronized(scanLock) {
                val dir = File(filesDir, "pending_lightning_captures")
                try {
                    if (!dir.exists() || !dir.isDirectory) return@execute
                    val nowMs = System.currentTimeMillis()
                    recoverOrphanPendingFilesLocked(dir, nowMs)

                    val files = dir.listFiles { f ->
                        f.extension.equals("jpg", ignoreCase = true) ||
                            f.extension.equals("jpeg", ignoreCase = true) ||
                            f.extension.equals("png", ignoreCase = true)
                    }
                    files?.sortBy { it.lastModified() }
                    files?.forEach { file ->
                        val originalName = file.name
                        val parsedFile = LightningAiBackgroundProcessor.getParsedResultFile(file)
                        val taskId = LightningAiBackgroundProcessor.getTaskIdForFile(originalName)

                        if (parsedFile.exists()) {
                            if (!isInForeground()) {
                                return@forEach
                            }
                            val ts = System.currentTimeMillis()
                            val processingImg = File(dir, "${originalName}__claim_${ts}.img.processing")
                            val processingParsed = File(dir, "${file.nameWithoutExtension}__claim_${ts}.parsed.processing")
                            val imgRenamed = file.renameTo(processingImg)
                            val parsedRenamed = parsedFile.renameTo(processingParsed)

                            if (imgRenamed && parsedRenamed) {
                                // 修复：重命名后立即刷新 mtime，防止 30s 过期误判重投
                                val claimNow = System.currentTimeMillis()
                                processingImg.setLastModified(claimNow)
                                processingParsed.setLastModified(claimNow)

                                try {
                                    val bytes = processingImg.readBytes()
                                    val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                    val mime = if (originalName.endsWith(".png", ignoreCase = true)) "image/png" else "image/jpeg"
                                    val dataUrl = "data:$mime;base64,$base64"
                                    val parsedJsonStr = processingParsed.readText(Charsets.UTF_8)

                                    mainHandler.post {
                                        dispatchParsedLightningToWebView(
                                            parsedJsonStr = parsedJsonStr,
                                            dataUrl = dataUrl,
                                            fileName = originalName
                                        ) { delivered ->
                                            if (!ingestionExecutor.isShutdown) {
                                                ingestionExecutor.execute {
                                                    if (delivered) {
                                                        notifiedInFlightTasks.remove(taskId)
                                                        try { processingImg.delete() } catch (_: Throwable) {}
                                                        try { processingParsed.delete() } catch (_: Throwable) {}
                                                    } else {
                                                        try { processingImg.renameTo(file) } catch (_: Throwable) {}
                                                        try { processingParsed.renameTo(parsedFile) } catch (_: Throwable) {}
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to ingest parsed lightning capture $originalName: ${e.message}")
                                    try { processingImg.renameTo(file) } catch (_: Throwable) {}
                                    try { processingParsed.renameTo(parsedFile) } catch (_: Throwable) {}
                                }
                            } else {
                                if (imgRenamed) try { processingImg.renameTo(file) } catch (_: Throwable) {}
                                if (parsedRenamed) try { processingParsed.renameTo(parsedFile) } catch (_: Throwable) {}
                            }
                        } else if (LightningAiBackgroundProcessor.isProcessing(originalName)) {
                            if (isInForeground()) {
                                notifyNativeParsingStartedInternal(file, taskId)
                            }
                        } else {
                            LightningAiBackgroundProcessor.enqueueCapture(applicationContext, file)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "scanPendingLightningCaptures error: ${e.message}")
                }
            }
        }
    }

    internal fun dispatchParsedLightningToWebView(
        parsedJsonStr: String,
        dataUrl: String,
        fileName: String,
        onComplete: (Boolean) -> Unit
    ) {
        val wv = webView
        if (wv == null || !isPageLoaded) {
            onComplete(false)
            return
        }
        val script = """
            (function() {
                if (typeof window.onNativeLightningParsed === 'function') {
                    return window.onNativeLightningParsed(${jsQuote(parsedJsonStr)}, ${jsQuote(dataUrl)}, ${jsQuote(fileName)}) ? 'true' : 'false';
                } else if (typeof window.onNativeScreenshotCaptured === 'function') {
                    window.onNativeScreenshotCaptured(${jsQuote(dataUrl)}, ${jsQuote(fileName)}, true);
                    return 'true';
                }
                return 'false';
            })();
        """.trimIndent()
        Log.i(TAG, "Dispatching pre-parsed lightning bill to WebView: fileName=$fileName")
        wv.evaluateJavascript(script) { result ->
            val cleanRes = result?.replace("\"", "")?.trim()
            val ok = cleanRes == "true"
            Log.i(TAG, "Pre-parsed lightning bill dispatched callback: evalResult=$result (ok=$ok)")
            onComplete(ok)
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
        val script = """
            if (typeof window.onNativeScreenshotCaptured === 'function') {
                window.onNativeScreenshotCaptured(${jsQuote(dataUrl)}, ${jsQuote(fileName)}, $isQuickTile);
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

        // 处理系统「分享」图片至 SingWallet 闪电记账队列
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("image/", ignoreCase = true) == true) {
            val sharedUri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            if (sharedUri != null) {
                handleSharedImageUri(sharedUri)
            }
            intent.action = null
            if (isFromCreate && webView != null) {
                webView?.loadUrl(resolveEntryUrl(intent))
            }
            return
        }

        val devUrlExtra = intent.getStringExtra("dev_url")
        val resetDev = intent.getBooleanExtra("reset_dev", false) || devUrlExtra.equals("off", ignoreCase = true)

        if (resetDev) {
            activeDevUrl = null
            webView?.settings?.apply {
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            }
            webView?.loadUrl(resolveEntryUrl(null))
            Log.i(TAG, "Switched back to built-in offline assets")
            Toast.makeText(this, "已切回内置离线版", Toast.LENGTH_SHORT).show()
        } else if (isAllowedLoopbackDevUrl(devUrlExtra)) {
            val cleanDevUrl = devUrlExtra!!.trim()
            activeDevUrl = cleanDevUrl
            webView?.settings?.apply {
                cacheMode = WebSettings.LOAD_NO_CACHE
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
            webView?.clearCache(true)
            webView?.loadUrl(cleanDevUrl)
            Log.i(TAG, "Loading live hot-reload dev_url: $cleanDevUrl")
            Toast.makeText(this, "已连接电脑 UI 实时热重载模式", Toast.LENGTH_SHORT).show()
        } else if (isFromCreate) {
            webView?.loadUrl(resolveEntryUrl(intent))
        }
    }

    private fun handleSharedImageUri(sharedUri: Uri) {
        if (ingestionExecutor.isShutdown) return
        Toast.makeText(this, "已接收账单截图，正在后台识别...", Toast.LENGTH_SHORT).show()

        LightningAiBackgroundProcessor.beginPreparingCapture()
        LightningAiForegroundService.startIfNeeded(applicationContext)

        try {
            ingestionExecutor.execute {
                var decoded: Bitmap? = null
                var scaled: Bitmap? = null
                var tmpFile: File? = null
                try {
                    val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    contentResolver.openInputStream(sharedUri)?.use { input ->
                        BitmapFactory.decodeStream(input, null, boundsOpts)
                    }
                    var sampleSize = 1
                    if (boundsOpts.outWidth > SHARE_TARGET_MAX_WIDTH) {
                        var halfW = boundsOpts.outWidth / 2
                        while (halfW / sampleSize >= SHARE_TARGET_MAX_WIDTH) {
                            sampleSize *= 2
                        }
                    }

                    val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
                    decoded = contentResolver.openInputStream(sharedUri)?.use { input ->
                        BitmapFactory.decodeStream(input, null, decodeOpts)
                    } ?: throw IllegalStateException("无法解码分享图片")

                    val targetBitmap = if (decoded.width > SHARE_TARGET_MAX_WIDTH) {
                        val scale = SHARE_TARGET_MAX_WIDTH.toFloat() / decoded.width.toFloat()
                        val targetH = (decoded.height * scale).toInt().coerceAtLeast(1)
                        scaled = Bitmap.createScaledBitmap(decoded, SHARE_TARGET_MAX_WIDTH, targetH, true)
                        scaled
                    } else {
                        decoded
                    }

                    val dir = File(filesDir, "pending_lightning_captures").apply { mkdirs() }
                    val ts = System.currentTimeMillis()
                    val candidateTmp = File(dir, "lightning_share_$ts.tmp")
                    tmpFile = candidateTmp
                    val finalFile = File(dir, "lightning_share_$ts.jpg")

                    BufferedOutputStream(FileOutputStream(candidateTmp), 16 * 1024).use { bos ->
                        if (!targetBitmap.compress(Bitmap.CompressFormat.JPEG, 85, bos)) {
                            throw IllegalStateException("压缩分享图片失败")
                        }
                        bos.flush()
                    }
                    if (!candidateTmp.renameTo(finalFile)) {
                        candidateTmp.copyTo(finalFile, overwrite = true)
                        candidateTmp.delete()
                    }

                    LightningAiBackgroundProcessor.enqueueCapture(applicationContext, finalFile)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to process shared image URI: ${e.message}", e)
                    try { tmpFile?.delete() } catch (_: Throwable) {}
                    mainHandler.post {
                        Toast.makeText(this@MainActivity, "读取分享图片失败: ${e.message}", Toast.LENGTH_SHORT).show()
                    }
                } finally {
                    LightningAiBackgroundProcessor.endPreparingCapture()
                    LightningAiForegroundService.stopIfIdle(applicationContext)
                    try { scaled?.recycle() } catch (_: Throwable) {}
                    try { decoded?.recycle() } catch (_: Throwable) {}
                }
            }
        } catch (t: Throwable) {
            LightningAiBackgroundProcessor.endPreparingCapture()
            LightningAiForegroundService.stopIfIdle(applicationContext)
            Log.e(TAG, "Failed to submit shared image task: ${t.message}", t)
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

    /**
     * 两阶段 ACK 消费第一阶段：将就绪结果重命名为 .ack_pending 并更新 mtime（超过 120s 未 ACK 自动还原），绝不直接删除
     */
    internal fun consumeReadyLightningCapturesInternal(): String {
        synchronized(scanLock) {
            val resultArr = JSONArray()
            val dir = File(filesDir, "pending_lightning_captures")
            if (!dir.exists() || !dir.isDirectory) {
                return resultArr.toString()
            }
            try {
                val nowMs = System.currentTimeMillis()
                recoverOrphanPendingFilesLocked(dir, nowMs)

                val files = dir.listFiles { f ->
                    f.extension.equals("jpg", ignoreCase = true) ||
                        f.extension.equals("jpeg", ignoreCase = true) ||
                        f.extension.equals("png", ignoreCase = true)
                }
                files?.sortBy { it.lastModified() }
                files?.forEach { file ->
                    val originalName = file.name
                    val parsedFile = LightningAiBackgroundProcessor.getParsedResultFile(file)
                    val taskId = LightningAiBackgroundProcessor.getTaskIdForFile(originalName)
                    if (parsedFile.exists()) {
                        val ackImg = File(dir, "${originalName}.img.ack_pending")
                        val ackParsed = File(dir, "${file.nameWithoutExtension}.parsed.json.ack_pending")
                        val imgRenamed = file.renameTo(ackImg)
                        val parsedRenamed = parsedFile.renameTo(ackParsed)
                        if (imgRenamed && parsedRenamed) {
                            val claimTs = System.currentTimeMillis()
                            ackImg.setLastModified(claimTs)
                            ackParsed.setLastModified(claimTs)
                            try {
                                val bytes = ackImg.readBytes()
                                val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                val mime = if (originalName.endsWith(".png", ignoreCase = true)) "image/png" else "image/jpeg"
                                val dataUrl = "data:$mime;base64,$base64"
                                val parsedJsonStr = ackParsed.readText(Charsets.UTF_8)
                                val itemObj = JSONObject().apply {
                                    put("fileName", originalName)
                                    put("dataUrl", dataUrl)
                                    put("parsedJson", parsedJsonStr)
                                }
                                resultArr.put(itemObj)
                                notifiedInFlightTasks.remove(taskId)
                            } catch (e: Exception) {
                                Log.w(TAG, "consumeReadyLightningCapturesInternal error for $originalName: ${e.message}")
                                try { ackImg.renameTo(file) } catch (_: Throwable) {}
                                try { ackParsed.renameTo(parsedFile) } catch (_: Throwable) {}
                            }
                        } else {
                            if (imgRenamed) try { ackImg.renameTo(file) } catch (_: Throwable) {}
                            if (parsedRenamed) try { ackParsed.renameTo(parsedFile) } catch (_: Throwable) {}
                        }
                    } else if (!LightningAiBackgroundProcessor.isProcessing(originalName)) {
                        LightningAiBackgroundProcessor.enqueueCapture(applicationContext, file)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "consumeReadyLightningCapturesInternal error: ${e.message}")
            }
            return resultArr.toString()
        }
    }

    /**
     * 两阶段 ACK 第二阶段：前端持久化完成后物理删除磁盘图片与解析结果
     */
    internal fun ackConsumedLightningCapturesInternal(fileNamesJson: String): Boolean {
        val names = mutableListOf<String>()
        try {
            val trimmed = fileNamesJson.trim()
            if (trimmed.startsWith("[")) {
                val arr = JSONArray(trimmed)
                for (i in 0 until arr.length()) {
                    arr.optString(i, "").trim().takeIf { it.isNotEmpty() }?.let { names.add(it) }
                }
            } else if (trimmed.isNotEmpty()) {
                trimmed.split(",").map { it.trim() }.filter { it.isNotEmpty() }.let { names.addAll(it) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ackConsumedLightningCaptures invalid payload: ${e.message}")
            return false
        }

        if (names.isEmpty()) return true

        synchronized(scanLock) {
            val dir = File(filesDir, "pending_lightning_captures")
            if (!dir.exists()) return true
            for (rawName in names) {
                val safeName = File(rawName).name
                if (safeName.isEmpty()) continue
                val baseName = safeName.substringBeforeLast('.')
                val candidates = listOf(
                    File(dir, "${safeName}.img.ack_pending"),
                    File(dir, "${baseName}.parsed.json.ack_pending"),
                    File(dir, safeName),
                    File(dir, "${baseName}.parsed.json")
                )
                for (target in candidates) {
                    try {
                        if (target.exists()) target.delete()
                    } catch (_: Throwable) {}
                }
            }
            return true
        }
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        webView?.onResume()
        scanPendingLightningCaptures()
    }

    override fun onPause() {
        isForeground = false
        webView?.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        if (instance === this) {
            isForeground = false
            instance = null
        }
        mainHandler.removeCallbacksAndMessages(null)
        ingestionExecutor.shutdownNow()
        otaExecutor.shutdownNow()
        webView?.let { wv ->
            try {
                (wv.parent as? ViewGroup)?.removeView(wv)
                wv.loadUrl("about:blank")
                wv.clearHistory()
                wv.removeAllViews()
                wv.destroy()
            } catch (e: Throwable) {
                Log.w(TAG, "Error destroying WebView: ${e.message}")
            }
        }
        webView = null
        super.onDestroy()
    }

    private fun saveBytesToDownloads(
        bytes: ByteArray,
        safeFileName: String,
        mimeType: String
    ): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, safeFileName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val itemUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Failed to create MediaStore.Downloads entry")
                resolver.openOutputStream(itemUri)?.use { out ->
                    out.write(bytes)
                    out.flush()
                } ?: throw IllegalStateException("Failed to open OutputStream for $itemUri")

                val completeValues = ContentValues().apply {
                    put(MediaStore.Downloads.IS_PENDING, 0)
                }
                resolver.update(itemUri, completeValues, null, null)
            } else {
                val downloadsDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    ?: File(filesDir, "downloads")
                if (!downloadsDir.exists()) downloadsDir.mkdirs()
                val targetFile = File(downloadsDir, safeFileName)
                FileOutputStream(targetFile).use { out ->
                    out.write(bytes)
                    out.flush()
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "saveBytesToDownloads failed for $safeFileName: ${e.message}", e)
            false
        }
    }

    private fun computeFileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(8192)
            var len: Int
            while (input.read(buf).also { len = it } != -1) {
                digest.update(buf, 0, len)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun parseWebManifestFiles(manifestStr: String): LinkedHashMap<String, String?>? {
        return try {
            val root = JSONObject(manifestStr)
            val filesObj = root.optJSONObject("files") ?: root
            val map = LinkedHashMap<String, String?>()
            val keys = filesObj.keys()
            while (keys.hasNext()) {
                val rawKey = keys.next()
                if (rawKey in setOf("version", "commitSha", "generatedAt", "updatedAt")) continue
                val cleanPath = rawKey.trimStart('/')
                if (cleanPath.isEmpty() || cleanPath.contains("..") || cleanPath.contains("\\")) continue
                val entry = filesObj.opt(rawKey)
                val sha = when (entry) {
                    is JSONObject -> entry.optString("sha256", "").trim().takeIf { SHA256_HEX_REGEX.matches(it) }
                    is String -> entry.trim().takeIf { SHA256_HEX_REGEX.matches(it) }
                    else -> null
                }
                map[cleanPath] = sha
            }
            if (map.isNotEmpty()) map else null
        } catch (_: Exception) {
            null
        }
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
                    val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vm = activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                        vm?.defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    }
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

        // ==========================================
        //  SQLite 12 核心表持久化 & 桥接 KV 接口
        // ==========================================

        @JavascriptInterface
        fun dbSaveTransactionsJson(jsonStr: String): Boolean {
            return SingWalletDatabaseHelper.getInstance(activity).saveTransactionsJson(jsonStr)
        }

        @JavascriptInterface
        fun dbLoadTransactionsJson(): String {
            return SingWalletDatabaseHelper.getInstance(activity).loadTransactionsJson()
        }

        @JavascriptInterface
        fun dbSaveKeyValue(key: String, value: String): Boolean {
            return SingWalletDatabaseHelper.getInstance(activity).saveKeyValue(key, value)
        }

        @JavascriptInterface
        fun dbLoadKeyValue(key: String): String {
            return SingWalletDatabaseHelper.getInstance(activity).loadKeyValue(key)
        }

        // ==========================================
        //  SWBK v1 加密备份 / CSV BOM 导出 / 明文 JSON 兼容导出
        // ==========================================

        @JavascriptInterface
        fun saveBackupFile(jsonContent: String, fileName: String): Boolean {
            val safeFileName = File(fileName.ifBlank { "singwallet_backup_${System.currentTimeMillis()}.json" }).name
            val ok = activity.saveBytesToDownloads(
                jsonContent.toByteArray(Charsets.UTF_8),
                safeFileName,
                "application/json"
            )
            activity.runOnUiThread {
                Toast.makeText(
                    activity,
                    if (ok) "备份已保存至系统下载目录: $safeFileName" else "保存备份文件失败",
                    Toast.LENGTH_SHORT
                ).show()
            }
            return ok
        }

        @JavascriptInterface
        fun saveSwbkBackupFile(jsonPayload: String, password: String, fileName: String): Boolean {
            return try {
                val swbkBytes = SwbkCryptoCodec.encrypt(jsonPayload, password)
                val baseName = File(fileName.ifBlank { "singwallet_backup_${System.currentTimeMillis()}.swbk" }).name
                val safeFileName = if (baseName.endsWith(".swbk", ignoreCase = true)) baseName else "$baseName.swbk"
                val ok = activity.saveBytesToDownloads(swbkBytes, safeFileName, "application/octet-stream")
                activity.runOnUiThread {
                    Toast.makeText(
                        activity,
                        if (ok) "加密备份已保存至系统下载目录: $safeFileName" else "保存加密备份失败",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                ok
            } catch (e: Exception) {
                Log.e(TAG, "saveSwbkBackupFile failed: ${e.message}", e)
                activity.runOnUiThread {
                    Toast.makeText(activity, "生成加密备份失败: ${e.message}", Toast.LENGTH_SHORT).show()
                }
                false
            }
        }

        @JavascriptInterface
        fun decryptSwbkBase64(base64Data: String, password: String): String {
            return try {
                val bytes = Base64.decode(base64Data, Base64.DEFAULT)
                SwbkCryptoCodec.decrypt(bytes, password)
            } catch (e: Exception) {
                Log.w(TAG, "decryptSwbkBase64 failed: ${e.message}")
                ""
            }
        }

        @JavascriptInterface
        fun saveCsvExportFile(csvContent: String, fileName: String): Boolean {
            return try {
                val baseName = File(fileName.ifBlank { "singwallet_export_${System.currentTimeMillis()}.csv" }).name
                val safeFileName = if (baseName.endsWith(".csv", ignoreCase = true)) baseName else "$baseName.csv"
                val bodyWithoutBom = csvContent.removePrefix("\uFEFF")
                val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
                val bodyBytes = bodyWithoutBom.toByteArray(Charsets.UTF_8)
                val outputStream = ByteArrayOutputStream(bom.size + bodyBytes.size).apply {
                    write(bom)
                    write(bodyBytes)
                }
                val ok = activity.saveBytesToDownloads(outputStream.toByteArray(), safeFileName, "text/csv")
                activity.runOnUiThread {
                    Toast.makeText(
                        activity,
                        if (ok) "CSV 账单已导出至下载目录: $safeFileName" else "导出 CSV 失败",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                ok
            } catch (e: Exception) {
                Log.e(TAG, "saveCsvExportFile failed: ${e.message}", e)
                false
            }
        }

        @JavascriptInterface
        fun pickAndImportBackupFile() {
            activity.runOnUiThread {
                activity.launchBackupFilePicker()
            }
        }

        @JavascriptInterface
        fun getAppVersion(): String = activity.getAppVersion()

        @JavascriptInterface
        fun isNativeApp(): Boolean = true

        @JavascriptInterface
        fun isAccessibilityServiceEnabled(): Boolean {
            return SingWalletAccessibilityService.isServiceRunning() ||
                SingWalletAccessibilityService.checkAccessibilityEnabled(activity)
        }

        @JavascriptInterface
        fun syncAiConfigToNative(configJson: String) {
            LightningAiBackgroundProcessor.saveAiConfig(activity, configJson)
        }

        @JavascriptInterface
        fun consumeReadyLightningCaptures(): String {
            return activity.consumeReadyLightningCapturesInternal()
        }

        @JavascriptInterface
        fun ackConsumedLightningCaptures(fileNamesJson: String): Boolean {
            return activity.ackConsumedLightningCapturesInternal(fileNamesJson)
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

        @JavascriptInterface
        fun performWebHotUpdate(configJson: String) {
            if (activity.otaExecutor.isShutdown) return
            activity.otaExecutor.execute {
                val config = try {
                    if (configJson.isNotBlank()) JSONObject(configJson) else JSONObject()
                } catch (_: Exception) {
                    JSONObject()
                }
                val repo = config.optString("repo", DEFAULT_REPO).ifBlank { DEFAULT_REPO }.trim()
                val branch = config.optString("branch", DEFAULT_BRANCH).ifBlank { DEFAULT_BRANCH }.trim()
                val version = config.optString("version", "")
                val commitSha = config.optString("commitSha", "").trim()

                if (!REPO_REGEX.matches(repo) || repo != DEFAULT_REPO) {
                    activity.dispatchOtaProgress(0, "热更新拒绝不受信任的仓库: $repo", true, "Untrusted repo: $repo", version, commitSha)
                    return@execute
                }
                val targetRef = if (commitSha.isNotEmpty()) commitSha else branch
                if (!REF_REGEX.matches(targetRef) || targetRef.contains("..")) {
                    activity.dispatchOtaProgress(0, "非法的更新引用: $targetRef", true, "Invalid ref", version, commitSha)
                    return@execute
                }

                val incomingToken = config.optString("token", "").trim()
                if (incomingToken.isNotEmpty()) {
                    SecureKeyStore.setGithubToken(activity, incomingToken)
                }
                val token = SecureKeyStore.getGithubToken(activity)

                val stagingDir = File(activity.filesDir, "web_hot_staging")
                try {
                    stagingDir.deleteRecursively()
                    stagingDir.mkdirs()

                    activity.dispatchOtaProgress(5, "开始检查并下载热更资源...", false, null, version, commitSha)

                    fun buildCandidateUrls(remotePath: String): List<String> {
                        return if (token.isNotEmpty()) {
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
                    }

                    // 尝试拉取 web/web_manifest.json 执行逐文件 SHA-256 校验
                    val manifestFile = File(stagingDir, "__web_manifest.json")
                    var manifestMap: LinkedHashMap<String, String?>? = null
                    for (manifestUrl in buildCandidateUrls("web/web_manifest.json")) {
                        try {
                            activity.downloadUrlToFile(manifestUrl, manifestFile, token.ifBlank { null })
                            if (manifestFile.exists() && manifestFile.length() > 0L) {
                                manifestMap = activity.parseWebManifestFiles(manifestFile.readText(Charsets.UTF_8))
                                if (manifestMap != null) break
                            }
                        } catch (_: Throwable) {
                        } finally {
                            if (manifestFile.exists()) manifestFile.delete()
                        }
                    }

                    val targetFiles: Map<String, String?> = manifestMap
                        ?: HOT_MUTABLE_FILES.associateWith { null }

                    val totalFiles = targetFiles.size.coerceAtLeast(1)
                    var indexHtmlContent = ""
                    var idx = 0

                    for ((relPath, expectedFileSha) in targetFiles) {
                        val stagingFile = File(stagingDir, relPath)
                        val stagingCanonical = stagingFile.canonicalPath
                        if (!stagingCanonical.startsWith(stagingDir.canonicalPath + File.separator)) {
                            throw SecurityException("热更路径非法: $relPath")
                        }
                        stagingFile.parentFile?.mkdirs()

                        var fileDownloaded = false
                        var lastErr: Throwable? = null

                        for (urlStr in buildCandidateUrls("web/$relPath")) {
                            try {
                                activity.downloadUrlToFile(urlStr, stagingFile, token.ifBlank { null })
                                if (!stagingFile.exists() || stagingFile.length() == 0L) {
                                    stagingFile.delete()
                                    continue
                                }
                                if (expectedFileSha != null) {
                                    val actualSha = activity.computeFileSha256(stagingFile)
                                    if (!actualSha.equals(expectedFileSha, ignoreCase = true)) {
                                        stagingFile.delete()
                                        throw SecurityException("文件 $relPath SHA-256 校验失败")
                                    }
                                }
                                if (relPath == "index.html") {
                                    val content = stagingFile.readText(Charsets.UTF_8)
                                    if (!content.contains("<html", ignoreCase = true)) {
                                        stagingFile.delete()
                                        throw IllegalStateException("index.html 校验失败: 缺少 <html 标签")
                                    }
                                    indexHtmlContent = content
                                }
                                fileDownloaded = true
                                break
                            } catch (t: Throwable) {
                                lastErr = t
                                Log.w(TAG, "Download attempt failed for $relPath ($urlStr): ${t.message}")
                                if (stagingFile.exists()) stagingFile.delete()
                            }
                        }

                        if (!fileDownloaded) {
                            val isOptionalCompat = manifestMap == null &&
                                relPath in OPTIONAL_COMPAT_FILES &&
                                !indexHtmlContent.contains(relPath)
                            if (!isOptionalCompat) {
                                throw IllegalStateException("文件 $relPath 下载或校验失败: ${lastErr?.message}")
                            }
                        }

                        idx++
                        val percent = 10 + (idx * 80 / totalFiles)
                        activity.dispatchOtaProgress(
                            percent,
                            "已更新组件 ($idx/$totalFiles): ${relPath.substringAfterLast('/')}",
                            false,
                            null,
                            version,
                            commitSha
                        )
                    }

                    // 全部校验通过后原子替换 web_hot_bundle
                    val hotBundleDir = File(activity.filesDir, "web_hot_bundle")
                    val backupBundleDir = File(activity.filesDir, "web_hot_bundle_old")
                    if (backupBundleDir.exists()) backupBundleDir.deleteRecursively()
                    if (hotBundleDir.exists()) {
                        if (!hotBundleDir.renameTo(backupBundleDir)) {
                            hotBundleDir.deleteRecursively()
                        }
                    }
                    if (!stagingDir.renameTo(hotBundleDir)) {
                        hotBundleDir.mkdirs()
                        stagingDir.copyRecursively(hotBundleDir, overwrite = true)
                        stagingDir.deleteRecursively()
                    }
                    if (backupBundleDir.exists()) backupBundleDir.deleteRecursively()

                    val prefs = activity.getSharedPreferences(PREFS_OTA, MODE_PRIVATE)
                    prefs.edit()
                        .putString(KEY_HOT_VERSION, version)
                        .putString(KEY_HOT_COMMIT_SHA, commitSha)
                        .putLong(KEY_HOT_UPDATED_AT, System.currentTimeMillis())
                        .apply()

                    activity.dispatchOtaProgress(100, "热更完成，正在重新加载页面...", true, null, version, commitSha)

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

        @JavascriptInterface
        fun downloadAndInstallApk(apkUrl: String, expectedSha256: String?) {
            if (activity.otaExecutor.isShutdown) return
            activity.otaExecutor.execute {
                val parsedUri = try {
                    Uri.parse(apkUrl.trim())
                } catch (_: Exception) {
                    null
                }
                val host = parsedUri?.host?.lowercase(Locale.ROOT).orEmpty()
                val isTrustedApkHost = parsedUri?.scheme.equals("https", ignoreCase = true) && (
                    host == "github.com" ||
                        host == "ghfast.top" ||
                        host.endsWith(".githubusercontent.com")
                    )
                if (!isTrustedApkHost) {
                    val msg = "拒绝下载非官方 HTTPS 安装包来源: $apkUrl"
                    activity.dispatchOtaProgress(0, msg, true, msg)
                    return@execute
                }

                val otaDir = File(activity.cacheDir, "ota_apk").apply { mkdirs() }
                val apkFile = File(otaDir, "singwallet-update.apk")
                if (apkFile.exists()) apkFile.delete()

                val savedToken = SecureKeyStore.getGithubToken(activity).ifBlank { null }

                // 若未传入 SHA-256，自动尝试从同 Release 路径获取 version.json 解析 sha256
                var resolvedSha256 = expectedSha256?.trim().orEmpty()
                if (resolvedSha256.isEmpty()) {
                    val versionJsonUrl = apkUrl.trim().substringBeforeLast('/') + "/version.json"
                    val versionCandidates = mutableListOf(versionJsonUrl)
                    if (versionJsonUrl.contains("github.com") && !versionJsonUrl.startsWith("https://ghfast.top/")) {
                        versionCandidates.add("https://ghfast.top/$versionJsonUrl")
                    }
                    val tmpVersionFile = File(otaDir, "version.json")
                    for (vUrl in versionCandidates) {
                        try {
                            activity.downloadUrlToFile(vUrl, tmpVersionFile, savedToken)
                            if (tmpVersionFile.exists() && tmpVersionFile.length() > 0L) {
                                val vJson = JSONObject(tmpVersionFile.readText(Charsets.UTF_8))
                                val parsed = vJson.optString("sha256", "").trim()
                                if (SHA256_HEX_REGEX.matches(parsed)) {
                                    resolvedSha256 = parsed
                                    break
                                }
                            }
                        } catch (_: Throwable) {
                        } finally {
                            if (tmpVersionFile.exists()) tmpVersionFile.delete()
                        }
                    }
                }

                if (!SHA256_HEX_REGEX.matches(resolvedSha256)) {
                    val msg = "安全校验拦截：缺少有效的 64 位安装包 SHA-256 摘要，已取消安装"
                    activity.dispatchOtaProgress(0, msg, true, msg)
                    return@execute
                }

                val candidateUrls = mutableListOf(apkUrl.trim())
                if (apkUrl.contains("github.com") && !apkUrl.startsWith("https://ghfast.top/")) {
                    candidateUrls.add("https://ghfast.top/${apkUrl.trim()}")
                }

                var downloaded = false
                var lastErr: Throwable? = null

                for (targetUrl in candidateUrls) {
                    try {
                        Log.i(TAG, "Attempting APK download from: $targetUrl")
                        activity.dispatchOtaProgress(0, "正在连接下载节点...", false, null)
                        var lastPercent = -1
                        var lastTime = 0L

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

                // 强制 SHA-256 完整性校验
                activity.dispatchOtaProgress(99, "正在校验安装包 SHA-256 完整性...", false, null)
                val actualSha256 = activity.computeFileSha256(apkFile)
                if (!actualSha256.equals(resolvedSha256, ignoreCase = true)) {
                    apkFile.delete()
                    val errMsg = "SHA-256 校验不匹配 (预期: $resolvedSha256, 实际: $actualSha256)"
                    Log.e(TAG, errMsg)
                    activity.dispatchOtaProgress(0, errMsg, true, errMsg)
                    return@execute
                }

                activity.dispatchOtaProgress(100, "安装包校验通过，正在调起系统安装...", true, null)

                activity.mainHandler.post {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !activity.packageManager.canRequestPackageInstalls()
                        ) {
                            Toast.makeText(activity, "请允许 SingWallet 安装未知来源应用后重试", Toast.LENGTH_LONG).show()
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            activity.startActivity(permIntent)
                            return@post
                        }

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

        @JavascriptInterface
        fun rollbackWebHotUpdate(): Boolean {
            return try {
                val hotDir = File(activity.filesDir, "web_hot_bundle")
                if (hotDir.exists()) {
                    hotDir.deleteRecursively()
                }
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
                true
            } catch (e: Exception) {
                Log.e(TAG, "rollbackWebHotUpdate failed: ${e.message}", e)
                false
            }
        }
    }
}
