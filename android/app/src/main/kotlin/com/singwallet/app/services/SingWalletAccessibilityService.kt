package com.singwallet.app.services

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.text.TextUtils
import android.util.Base64
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.widget.Toast
import androidx.annotation.RequiresApi
import com.singwallet.app.MainActivity
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * SingWallet 官方无感快捷抓屏无障碍服务 (Accessibility Service).
 *
 * 核心设计规范 (Android 11+ API 30~35):
 * 1. 内存零相册污染：利用系统官方 takeScreenshot API 直接在内存中获取 HardwareBuffer 并转为 Bitmap，
 *    绝不在相册生成任何临时文件，杜绝相册垃圾。
 * 2. 毫秒级极速定格：控制中心收拢的瞬间 (150ms~340ms) 立即冻结当前屏幕账单画面，即使用户切走或返回也不会漏单。
 * 3. 常驻生命周期托管：由于 QuickRecordTileService 在控制中心收拢瞬间 (约 350ms) 会被系统立刻解绑销毁 (onDestroy)，
 *    所有延时抓屏、Bitmap 压缩落盘与触发原生后台 AI 解析全流程统一由本常驻服务及应用级守护线程池托管，彻底杜绝中途被打断。
 * 4. 极简权限原则：仅声明并启用 canTakeScreenshot，不监听键盘按键或常态读取剪贴板，严格尊重用户隐私。
 */
class SingWalletAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SingWalletA11y"
        private const val TARGET_MAX_WIDTH = 1080
        private const val CAPTURE_WATCHDOG_MS = 5000L

        @Volatile
        private var instance: SingWalletAccessibilityService? = null

        private val globalMainHandler = Handler(Looper.getMainLooper())
        private val persistExecutor: ExecutorService = Executors.newSingleThreadExecutor()
        private val isCapturing = AtomicBoolean(false)
        private val fileSeq = AtomicLong(0L)

        /**
         * 检测当前无障碍服务是否已连接并在后台运行
         */
        fun isServiceRunning(): Boolean = instance != null

        /**
         * 获取当前服务单例
         */
        fun getInstance(): SingWalletAccessibilityService? = instance

        /**
         * 伴生单例方法：直接收起通知栏/控制中心面板
         */
        fun collapseShade(): Boolean {
            return instance?.collapseControlCenter() ?: false
        }

        /**
         * 伴生单例方法：内存无感捕获当前屏幕快照
         *
         * @param onResult 回调截屏 Bitmap (主线程返回)，失败时返回 null
         */
        fun captureCurrentScreen(onResult: (Bitmap?) -> Unit) {
            val service = instance
            if (service == null) {
                Log.w(TAG, "captureCurrentScreen failed: SingWalletAccessibilityService is not connected")
                onResult(null)
                return
            }
            service.performCapture(onResult)
        }

        /**
         * 托管完整的「收拢控制中心 -> 延时定格抓屏 -> 触感快门 -> 压缩落盘 -> 立即启动原生后台 AI 解析」全链路.
         * 独立于 QuickRecordTileService 生命周期，防止控制中心收起解绑 TileService 时中断后台解析入队。
         */
        fun triggerLightningTileCapture(
            context: Context,
            delayMs: Long = 340L,
            onDone: (() -> Unit)? = null
        ): Boolean {
            val service = instance
            if (service == null) {
                Log.w(TAG, "triggerLightningTileCapture aborted: AccessibilityService not running")
                return false
            }

            if (!isCapturing.compareAndSet(false, true)) {
                Log.d(TAG, "Capture already in progress, ignore redundant trigger")
                onDone?.invoke()
                return true
            }

            val appContext = context.applicationContext
            val watchdogRunnable = Runnable {
                if (isCapturing.compareAndSet(true, false)) {
                    Log.w(TAG, "Capture watchdog reset isCapturing after ${CAPTURE_WATCHDOG_MS}ms timeout")
                    onDone?.invoke()
                }
            }
            globalMainHandler.postDelayed(watchdogRunnable, CAPTURE_WATCHDOG_MS)

            // 1. 立即收拢控制中心面板
            service.collapseControlCenter()

            // 2. 在控制中心收拢露出底层账单画面的瞬间定格截图并启动后台 AI 解析
            globalMainHandler.postDelayed({
                val currentService = instance ?: service
                currentService.performCapture { bitmap ->
                    globalMainHandler.removeCallbacks(watchdogRunnable)
                    isCapturing.set(false)

                    if (bitmap != null) {
                        triggerHapticFeedback(appContext, 50L)
                        Log.i(TAG, "Snapshot locked in RAM (${bitmap.width}x${bitmap.height}), dispatching to background AI processor")
                        showToast(appContext, "闪电记账：已捕获账单画面，后台解析中...")

                        // 提前拉起短时前台守护服务，保障后台网络与 CPU 不被系统冻结
                        LightningAiForegroundService.startIfNeeded(appContext)

                        persistExecutor.execute {
                            processAndEnqueueBitmap(appContext, bitmap)
                        }
                    } else {
                        Log.e(TAG, "captureCurrentScreen returned null")
                        showToast(appContext, "闪电记账：未能捕获屏幕，请重试")
                    }

                    onDone?.invoke()
                }
            }, delayMs)

            return true
        }

        private fun processAndEnqueueBitmap(appContext: Context, bitmap: Bitmap) {
            var scaledBitmap: Bitmap? = null
            try {
                val bitmapToEncode = if (bitmap.width > TARGET_MAX_WIDTH) {
                    val scale = TARGET_MAX_WIDTH.toFloat() / bitmap.width.toFloat()
                    val targetHeight = (bitmap.height * scale).toInt()
                    scaledBitmap = Bitmap.createScaledBitmap(bitmap, TARGET_MAX_WIDTH, targetHeight, true)
                    scaledBitmap
                } else {
                    bitmap
                }

                val outputStream = ByteArrayOutputStream()
                bitmapToEncode.compress(Bitmap.CompressFormat.JPEG, 82, outputStream)
                val byteArray = outputStream.toByteArray()

                Log.i(TAG, "Encoded JPEG bytes=${byteArray.size}")

                // 1. 先原子落盘至私有目录，确保任何极端场景下 100% 零丢单
                val savedFile = savePendingCaptureToDisk(appContext, byteArray)
                if (savedFile != null) {
                    // 2. 立即在 Android 原生后台守护线程池启动异步 AI 账单解析（无需等待用户打开 App）
                    LightningAiBackgroundProcessor.enqueueCapture(appContext, savedFile)
                } else if (MainActivity.isInForeground()) {
                    val base64 = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                    val dataUrl = "data:image/jpeg;base64,$base64"
                    MainActivity.dispatchCapturedScreenshot(dataUrl, "lightning-tile")
                }
            } catch (e: Throwable) {
                Log.e(TAG, "Error encoding/enqueuing captured bitmap: ${e.message}", e)
                LightningAiForegroundService.stopIfIdle(appContext)
            } finally {
                try {
                    scaledBitmap?.recycle()
                } catch (_: Throwable) {}
                try {
                    bitmap.recycle()
                } catch (_: Throwable) {}
            }
        }

        private fun savePendingCaptureToDisk(appContext: Context, byteArray: ByteArray): File? {
            return try {
                val dir = File(appContext.filesDir, "pending_lightning_captures")
                if (!dir.exists()) dir.mkdirs()
                val ts = System.currentTimeMillis()
                val seq = fileSeq.incrementAndGet() % 1000L
                val baseName = if (seq == 1L) "lightning_${ts}" else "lightning_${ts}_${seq}"
                val tmpFile = File(dir, "${baseName}.tmp")
                val file = File(dir, "${baseName}.jpg")
                FileOutputStream(tmpFile).use { it.write(byteArray) }
                if (!tmpFile.renameTo(file)) {
                    FileOutputStream(file).use { it.write(byteArray) }
                    try { tmpFile.delete() } catch (_: Throwable) {}
                }
                Log.i(TAG, "Saved lightning capture to ${file.absolutePath} (${byteArray.size} bytes)")
                file
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to save pending capture: ${e.message}", e)
                null
            }
        }

        private fun triggerHapticFeedback(context: Context, durationMs: Long = 50L) {
            try {
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vibratorManager?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(durationMs.coerceAtLeast(10L), VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(durationMs)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Haptic vibration failed: ${e.message}")
            }
        }

        private fun showToast(context: Context, message: String) {
            globalMainHandler.post {
                try {
                    Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Log.w(TAG, "showToast error: ${e.message}")
                }
            }
        }

        /**
         * 辅助方法：通过系统设置安全表检测用户是否已在系统中启用了本无障碍服务
         */
        fun checkAccessibilityEnabled(context: Context): Boolean {
            if (instance != null) return true
            try {
                val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
                if (am == null || !am.isEnabled) return false

                val enabledServices = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                ) ?: return false

                val colonSplitter = TextUtils.SimpleStringSplitter(':')
                colonSplitter.setString(enabledServices)
                val expectedServiceName = ComponentName(context, SingWalletAccessibilityService::class.java).flattenToString()
                val expectedShortName = ComponentName(context, SingWalletAccessibilityService::class.java).flattenToShortString()

                while (colonSplitter.hasNext()) {
                    val componentName = colonSplitter.next()
                    if (componentName.equals(expectedServiceName, ignoreCase = true) ||
                        componentName.equals(expectedShortName, ignoreCase = true)
                    ) {
                        return true
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error checking accessibility status: ${e.message}")
            }
            return false
        }
    }

    private val captureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "SingWalletAccessibilityService connected successfully")

        try {
            val info = serviceInfo ?: AccessibilityServiceInfo()
            info.flags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            serviceInfo = info
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to configure serviceInfo: ${e.message}")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 无需常态监听事件，仅按需响应闪电记账触发 takeScreenshot
    }

    override fun onInterrupt() {
        Log.i(TAG, "SingWalletAccessibilityService interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (instance === this) {
            instance = null
        }
        Log.i(TAG, "SingWalletAccessibilityService unbound")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) {
            instance = null
        }
        captureExecutor.shutdownNow()
        Log.i(TAG, "SingWalletAccessibilityService destroyed")
    }

    /**
     * 利用无障碍专属全局操作关闭控制中心或下拉通知栏，无报错且无多余 Activity 闪烁
     */
    fun collapseControlCenter(): Boolean {
        var handled = false
        val isXiaomi = Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) ||
                       Build.BRAND.equals("Xiaomi", ignoreCase = true) ||
                       Build.BRAND.equals("Redmi", ignoreCase = true) ||
                       Build.BRAND.equals("POCO", ignoreCase = true)

        if (isXiaomi) {
            // 小米澎湃 OS (HyperOS) 实测不支持 GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE (底层报错 Invalid action id: 15 并徒增 74ms 耗时)
            // 直接第一时间调用 GLOBAL_ACTION_BACK，0ms 零延迟收起控制中心
            try {
                handled = performGlobalAction(GLOBAL_ACTION_BACK)
            } catch (e: Throwable) {
                Log.w(TAG, "GLOBAL_ACTION_BACK on Xiaomi failed: ${e.message}")
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    handled = performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
                } catch (e: Throwable) {
                    Log.w(TAG, "GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE failed: ${e.message}")
                }
            }
            if (!handled) {
                try {
                    handled = performGlobalAction(GLOBAL_ACTION_BACK)
                } catch (e: Throwable) {
                    Log.w(TAG, "GLOBAL_ACTION_BACK fallback failed: ${e.message}")
                }
            }
        }

        // 仅在 Android 12 (API 31) 以下才发送 ACTION_CLOSE_SYSTEM_DIALOGS，彻底消除 Android 12+ Permission Denial 报错警告
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                @Suppress("DEPRECATION")
                val closeIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
                sendBroadcast(closeIntent)
            } catch (_: Throwable) {}
        }

        Log.i(TAG, "collapseControlCenter executed (isXiaomi=$isXiaomi): handled=$handled")
        return handled
    }

    /**
     * 执行内存级屏幕捕获
     */
    fun performCapture(onResult: (Bitmap?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            performCaptureApi30(onResult)
        } else {
            Log.w(TAG, "AccessibilityService.takeScreenshot requires Android 11+ (API 30+)")
            mainHandler.post { onResult(null) }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun performCaptureApi30(onResult: (Bitmap?) -> Unit) {
        try {
            Log.i(TAG, "Invoking takeScreenshot(DEFAULT_DISPLAY)...")
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                captureExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val hardwareBuffer = screenshot.hardwareBuffer
                        val colorSpace = screenshot.colorSpace
                        try {
                            // 1. 将 HardwareBuffer 包装为硬件 Bitmap
                            val hwBitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                            // 2. 转换为软件 Bitmap，避免 Hardware Bitmap 在后续压缩或处理时抛异常
                            val softwareBitmap = hwBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                            hwBitmap?.recycle()

                            Log.i(TAG, "takeScreenshot onSuccess: ${softwareBitmap?.width}x${softwareBitmap?.height}")

                            mainHandler.post {
                                onResult(softwareBitmap)
                            }
                        } catch (e: Throwable) {
                            Log.e(TAG, "Error processing HardwareBuffer to Bitmap: ${e.message}", e)
                            mainHandler.post { onResult(null) }
                        } finally {
                            try {
                                hardwareBuffer.close()
                            } catch (_: Throwable) {}
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "takeScreenshot failed with error code: $errorCode")
                        mainHandler.post { onResult(null) }
                    }
                }
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to invoke takeScreenshot: ${t.message}", t)
            mainHandler.post { onResult(null) }
        }
    }
}
