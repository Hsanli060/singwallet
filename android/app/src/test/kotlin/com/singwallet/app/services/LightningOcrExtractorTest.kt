package com.singwallet.app.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LightningOcrExtractorTest {

    @Test
    fun extractBillFromOcrLines_extractsWeChatBillFields() {
        val lines = listOf(
            "账单详情",
            "星巴克咖啡(国贸店)",
            "-¥38.50",
            "当前状态",
            "支付成功",
            "支付时间",
            "2026-10-26 09:15:32",
            "支付方式",
            "中国招商银行储蓄卡(8848)",
            "交易单号",
            "4200002418202610269988776655"
        )

        val res = LightningAiBackgroundProcessor.extractBillFromOcrLines(lines)
        assertEquals(38.50, res.amount, 0.001)
        assertTrue(res.hasExplicitMerchant)
        assertEquals("星巴克咖啡(国贸店)", res.merchant)
        assertEquals("餐饮美食", res.category)
        assertEquals("微信", res.channel)
        assertEquals("招商银行(8848)", res.account)
        assertEquals("2026-10-26 09:15:32", res.time)
        assertEquals("4200002418202610269988776655", res.orderId)
        assertTrue(res.confidence >= 80.0)
    }

    @Test
    fun extractBillFromOcrLines_returnsZeroConfidenceWhenNoAmount() {
        val lines = listOf("网络异常", "请刷新重试")
        val res = LightningAiBackgroundProcessor.extractBillFromOcrLines(lines)
        assertEquals(0.0, res.amount, 0.001)
        assertEquals(0.0, res.confidence, 0.001)
    }

    @Test
    fun extractBillFromOcrLines_extractsAlipayWithHuabei() {
        val lines = listOf(
            "支付宝",
            "付款成功",
            "盒马鲜生",
            "实付金额 ￥128.40",
            "付款方式 花呗",
            "创建时间 2026-11-18 18:20:05",
            "订单号 202611182200148877665544"
        )
        val res = LightningAiBackgroundProcessor.extractBillFromOcrLines(lines)
        assertEquals(128.40, res.amount, 0.001)
        assertEquals("支付宝", res.channel)
        assertEquals("花呗", res.account)
        assertEquals("日常购物", res.category)
        assertEquals("2026-11-18 18:20:05", res.time)
        assertEquals("202611182200148877665544", res.orderId)
        assertFalse(res.confidence == 0.0)
    }
}
