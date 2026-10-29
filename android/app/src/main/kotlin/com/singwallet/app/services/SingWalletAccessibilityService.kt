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
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import androidx.annotation.RequiresApi
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * SingWallet 官方无感快捷抓屏无障碍服务 (Accessibility Service).
 *
 * 核心设计规范 (Android 11+ API 30~34):
 * 1. 内存零相册污染：利用系统官方 takeScreenshot API 直接在内存中获取 HardwareBuffer 并转为 Bitmap，
 *    绝不在相册生成任何临时文件，杜绝相册垃圾。
 * 2. 毫秒级极速定格：控制中心收拢的瞬间 (150ms~200ms) 立即冻结当前屏幕账单画面，即使用户切走或返回也不会漏单。
 * 3. 极简权限原则：仅声明并启用 canTakeScreenshot，不监听键盘按键或常态读取剪贴板，严格尊重用户隐私。
 */
class SingWalletAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SingWalletA11y"

        @Volatile
        private var instance: SingWalletAccessibilityService? = null

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
