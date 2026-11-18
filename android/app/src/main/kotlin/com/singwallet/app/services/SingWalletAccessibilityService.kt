package com.singwallet.app.services

import android.accessibilityservice.AccessibilityService
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
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.widget.Toast
import androidx.annotation.RequiresApi
import java.io.BufferedOutputStream
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
 *    流式直写入私有目录，绝不在相册生成任何临时文件。
 * 2. 极简省电原则：仅声明并启用 canTakeScreenshot，不订阅窗口内容变更事件、不读取界面控件树。
 * 3. 前台守护防竞态：在盘面准备开始即递增 preparingCount 并拉起 ForegroundService，直到入队完成才释放。
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

        fun isServiceRunning(): Boolean = instance != null

        fun getInstance(): SingWalletAccessibilityService? = instance

        fun collapseShade(): Boolean {
            return instance?.collapseControlCenter() ?: false
        }

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
         * 托管完整的「收拢控制中心 -> 延时定格抓屏 -> 触感快门 -> 流式落盘 -> 启动原生后台 AI/OCR 解析」全链路
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

            // 2. 在控制中心收拢露出底层账单画面的瞬间定格截图并启动后台解析
            globalMainHandler.postDelayed({
                val currentService = instance ?: service
                currentService.performCapture { bitmap ->
                    globalMainHandler.removeCallbacks(watchdogRunnable)
                    isCapturing.set(false)

                    if (bitmap != null) {
                        triggerHapticFeedback(appContext, 50L)
                        Log.i(TAG, "Snapshot locked in RAM (${bitmap.width}x${bitmap.height}), dispatching to background AI processor")
                        showToast(appContext, "闪电记账：已捕获账单画面，后台解析中...")

                        // 先标记 preparingCount 再启动短时前台守护服务，消除 stopIfIdle 竞态
                        LightningAiBackgroundProcessor.beginPreparingCapture()
                        LightningAiForegroundService.startIfNeeded(appContext)

                        try {
                            persistExecutor.execute {
                                processAndEnqueueBitmap(appContext, bitmap)
                            }
                        } catch (t: Throwable) {
                            Log.e(TAG, "Failed to submit bitmap persistence task: ${t.message}", t)
                            try {
                                bitmap.recycle()
                            } catch (_: Throwable) {}
                            LightningAiBackgroundProcessor.endPreparingCapture()
                            LightningAiForegroundService.stopIfIdle(appContext)
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
                    val targetHeight = (bitmap.height * scale).toInt().coerceAtLeast(1)
                    scaledBitmap = Bitmap.createScaledBitmap(bitmap, TARGET_MAX_WIDTH, targetHeight, true)
                    scaledBitmap
                } else {
                    bitmap
                }

                // 直接流式压缩落盘至私有目录，避免中间 ByteArrayOutputStream 内存峰值
                val savedFile = savePendingCaptureToDisk(appContext, bitmapToEncode)
                if (savedFile != null) {
                    LightningAiBackgroundProcessor.enqueueCapture(appContext, savedFile)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "Error encoding/enqueuing captured bitmap: ${e.message}", e)
            } finally {
                LightningAiBackgroundProcessor.endPreparingCapture()
                LightningAiForegroundService.stopIfIdle(appContext)
                try {
                    scaledBitmap?.recycle()
                } catch (_: Throwable) {}
                try {
                    bitmap.recycle()
                } catch (_: Throwable) {}
            }
        }

        private fun savePendingCaptureToDisk(appContext: Context, bitmap: Bitmap): File? {
            var tmpFile: File? = null
            return try {
                val dir = File(appContext.filesDir, "pending_lightning_captures")
                if (!dir.exists()) dir.mkdirs()
                val ts = System.currentTimeMillis()
                val seq = fileSeq.incrementAndGet() % 1000L
                val baseName = if (seq == 1L) "lightning_$ts" else "lightning_${ts}_$seq"
                val candidateTmp = File(dir, "$baseName.tmp")
                tmpFile = candidateTmp
                val finalFile = File(dir, "$baseName.jpg")

                BufferedOutputStream(FileOutputStream(candidateTmp), 16 * 1024).use { bos ->
                    val ok = bitmap.compress(Bitmap.CompressFormat.JPEG, 82, bos)
                    bos.flush()
                    if (!ok) {
                        throw IllegalStateException("Bitmap.compress returned false")
                    }
                }

                if (!candidateTmp.renameTo(finalFile)) {
                    candidateTmp.copyTo(finalFile, overwrite = true)
                    candidateTmp.delete()
                }
                Log.i(TAG, "Saved lightning capture to ${finalFile.absolutePath} (${finalFile.length()} bytes)")
                finalFile
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to save pending capture: ${e.message}", e)
                try {
                    tmpFile?.delete()
                } catch (_: Throwable) {}
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
        Log.i(TAG, "SingWalletAccessibilityService connected (low-power screenshot-only mode)")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 极简省电：不监听任何窗口事件，仅按需响应闪电记账触发 takeScreenshot
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

    fun collapseControlCenter(): Boolean {
        var handled = false
        val isXiaomi = Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) ||
            Build.BRAND.equals("Xiaomi", ignoreCase = true) ||
            Build.BRAND.equals("Redmi", ignoreCase = true) ||
            Build.BRAND.equals("POCO", ignoreCase = true)

        if (isXiaomi) {
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
                            val hwBitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
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
