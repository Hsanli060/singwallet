package com.singwallet.app.services

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import com.singwallet.app.MainActivity

/**
 * SingWallet 下拉控制中心「应用快捷开关」(Quick Settings Tile).
 *
 * 对应小米澎湃 OS (HyperOS)「控制中心 -> 编辑与排序 -> 应用快捷开关」中的快捷瓷贴。
 * 用户在微信/支付宝账单页下拉控制中心，轻点「闪电记账」即可触发无感抓屏记账。
 *
 * 核心优势：
 * 1. 零相册污染：通过内存直接捕获屏幕画面或在提取后即时清理，不在手机相册里留下一张垃圾截屏。
 * 2. 极速单手触发：在任何第三方 App 界面下拉控制中心一触即发。
 */
class QuickRecordTileService : TileService() {

    companion object {
        private const val TAG = "QuickRecordTile"
        const val ACTION_TRIGGER_QUICK_RECORD = "com.singwallet.app.action.QUICK_RECORD_CAPTURE"
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState(Tile.STATE_INACTIVE, "闪电记账", "轻点抓屏记账")
    }

    override fun onClick() {
        super.onClick()
        Log.i(TAG, "QuickRecordTile clicked by user in Control Center")

        // 1. 更新瓷贴为活动状态提示
        updateTileState(Tile.STATE_ACTIVE, "正在识别...", "抓取当前账单")

        // 2. 收起控制中心下拉面板 (针对 Android 14 / HyperOS 兼容处理)
        try {
            val closeIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            sendBroadcast(closeIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Unable to broadcast CLOSE_SYSTEM_DIALOGS: ${e.message}")
        }

        // 3. 调起后台/前端快速抓屏处理 Intent
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_TRIGGER_QUICK_RECORD
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("source", "quick_settings_tile")
            putExtra("timestamp", System.currentTimeMillis())
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }

        // 4. 短暂延迟后重置瓷贴状态
        qsTile?.let {
            it.state = Tile.STATE_INACTIVE
            it.label = "闪电记账"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.subtitle = "轻点抓屏记账"
            }
            it.updateTile()
        }
    }

    private fun updateTileState(state: Int, label: String, subtitle: String) {
        val tile = qsTile ?: return
        tile.state = state
        tile.label = label
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        tile.updateTile()
    }
}
