package com.singwallet.app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.singwallet.app.MainActivity
import com.singwallet.app.R

/**
 * SingWallet 闪电记账后台 AI 解析短时前台守护服务 (Short-Service Foreground Service).
 *
 * 核心职责：
 * 在 Android 12~15 (API 31~35) 及小米澎湃 OS (HyperOS) 下，当用户在微信/支付宝点击控制中心「闪电记账」时，
 * SingWallet 往往处于后台无 Activity 状态。若仅使用普通后台线程发起 HTTPS 大模型请求，
 * 极易遭遇系统 cgroup Freezer 冻结或后台省电防火墙阻断网络套接字。
 *
 * 通过启动 `shortService` 类型的前台服务（处理期间显示静默低优通知，解析落盘后毫秒级自动销毁），
 * 将进程提升至前台网络优先级，确保后台 VLM 大模型请求 100% 稳定、实时返回，用户打开 App 时账单已就绪。
 */
class LightningAiForegroundService : Service() {

    companion object {
        private const val TAG = "LightningAiFgService"
        private const val CHANNEL_ID = "singwallet_lightning_ai_channel"
        private const val NOTIFICATION_ID = 202608

        fun startIfNeeded(context: Context) {
            val appCtx = context.applicationContext
            try {
                val intent = Intent(appCtx, LightningAiForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appCtx.startForegroundService(intent)
                } else {
                    appCtx.startService(intent)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Unable to start LightningAiForegroundService (fallback to WakeLock thread): ${t.message}")
            }
        }

        fun stopIfIdle(context: Context) {
            if (LightningAiBackgroundProcessor.hasInFlightTasks()) {
                return
            }
            val appCtx = context.applicationContext
            try {
                val intent = Intent(appCtx, LightningAiForegroundService::class.java)
                appCtx.stopService(intent)
            } catch (t: Throwable) {
                Log.w(TAG, "Unable to stop LightningAiForegroundService: ${t.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        promoteToForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        if (!LightningAiBackgroundProcessor.hasInFlightTasks()) {
            stopForegroundSafely()
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) {
        Log.w(TAG, "LightningAiForegroundService reached shortService timeout, stopping gracefully")
        stopForegroundSafely()
        stopSelf(startId)
    }

    override fun onDestroy() {
        stopForegroundSafely()
        super.onDestroy()
    }

    private fun promoteToForeground() {
        try {
            ensureNotificationChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "promoteToForeground warning: ${t.message}")
        }
    }

    private fun stopForegroundSafely() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "闪电记账后台 AI 解析",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "保障闪电记账在后台实时调用 AI 大模型完成账单识别"
                    enableVibration(false)
                    setSound(null, null)
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("SingWallet 闪电记账")
            .setContentText("正在后台异步识别账单画面...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
