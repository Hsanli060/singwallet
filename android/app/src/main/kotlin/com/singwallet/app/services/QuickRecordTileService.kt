package com.singwallet.app.services

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.widget.Toast
import com.singwallet.app.R

/**
 * SingWallet 下拉控制中心「闪电记账」(Quick Settings Tile).
 *
 * 核心设计原则：
 * 1. 彻底移除强制切应用行为：控制中心收拢后，屏幕绝对留在微信/支付宝付款页，绝不跳转覆盖到 SingWallet。
 * 2. 生命周期解耦与防中断：Android 系统在控制中心面板收拢完成瞬间（约 350ms）会立即解绑并销毁 TileService (onDestroy)。
 *    因此，点击磁贴后直接将「延时定格抓屏 -> 压缩落盘 -> 启动原生后台 AI 账单解析」全权交由常驻的
 *    `SingWalletAccessibilityService.triggerLightningTileCapture()` 执行，确保后台 AI 解析 100% 完整走完。
 */
class QuickRecordTileService : TileService() {

    companion object {
        private const val TAG = "QuickRecordTile"
        private const val PANEL_COLLAPSE_DELAY_MS = 340L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onStartListening() {
        super.onStartListening()
        updateTileState(Tile.STATE_INACTIVE, "闪电记账", "轻点抓屏记账")
    }

    override fun onClick() {
        super.onClick()
        Log.i(TAG, "QuickRecordTile clicked by user in Control Center")

        // 1. 检查无障碍快捷抓屏服务是否运行
        val isServiceReady = SingWalletAccessibilityService.isServiceRunning()

        if (!isServiceReady) {
            Log.w(TAG, "SingWalletAccessibilityService is not running. Prompting user to enable.")
            showToast("请先开启 SingWallet 无障碍快捷抓屏服务")

            val settingsIntent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    settingsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                startActivityAndCollapse(pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(settingsIntent)
            }

            resetTileState()
            return
        }

        // 2. 更新瓷贴为活动捕获状态
        updateTileState(Tile.STATE_ACTIVE, "正在捕获...", "极速截取账单")

        // 3. 委派给常驻无障碍服务执行收拢控制中心、定格抓屏、落盘与原生后台 AI 异步解析（不受 TileService onDestroy 影响）
        SingWalletAccessibilityService.triggerLightningTileCapture(
            context = applicationContext,
            delayMs = PANEL_COLLAPSE_DELAY_MS
        ) {
            resetTileState()
        }
    }

    private fun showToast(message: String) {
        mainHandler.post {
            try {
                Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Log.w(TAG, "showToast error: ${e.message}")
            }
        }
    }

    private fun resetTileState() {
        mainHandler.post {
            try {
                updateTileState(Tile.STATE_INACTIVE, "闪电记账", "轻点抓屏记账")
            } catch (_: Throwable) {}
        }
    }

    private fun updateTileState(state: Int, label: String, subtitle: String) {
        val tile = qsTile ?: return
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_quick_record)
        tile.state = state
        tile.label = label
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        tile.updateTile()
    }
}
