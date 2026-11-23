package com.singwallet.app.services

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.singwallet.app.MainActivity
import com.singwallet.app.security.SecureKeyStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * SingWallet 原生后台异步 AI / 离线 ML Kit 账单解析引擎.
 *
 * 1. 敏感密钥通过 `SecureKeyStore` 硬件级 AES-GCM 加密读写，绝不落明文、不进 URL Query。
 * 2. 本地模式 (`ocrEngine == "local"`) 调用 Google ML Kit 中文离线 OCR + 账单结构化规则抽取，
 *    未识别出有效金额时明确返回错误原因提示用户确认，绝不编造假账单。
 * 3. 通过 `preparingCount` + `inFlightFiles` 消除前台守护服务的生命周期竞态。
 */
object LightningAiBackgroundProcessor {

    private const val TAG = "LightningAiBgProcessor"
    const val PREFS_AI = "singwallet_ai_prefs"

    private const val KEY_PROVIDER = "vlm_provider"
    private const val KEY_ENDPOINT = "vlm_endpoint"
    private const val KEY_MODEL = "vlm_model"
    private const val KEY_OCR_ENGINE = "ocr_engine"
    private const val KEY_CATEGORIES_JSON = "categories_json"
    private const val KEY_AUTO_COMMIT_ENABLED = "auto_commit_enabled"
    private const val KEY_AUTO_COMMIT_THRESHOLD = "auto_commit_threshold"

    private const val TOTAL_HTTP_DEADLINE_MS = 62_000L
    private const val ML_KIT_TIMEOUT_SEC = 15L

    private val DEFAULT_CATEGORIES = listOf(
        "餐饮美食", "交通出行", "日常购物", "休闲娱乐",
        "生活缴费", "医疗健康", "其他支出", "工资收入"
    )

    private const val MAX_BG_CONCURRENCY = 4
    private const val THREAD_IDLE_TIMEOUT_SEC = 30L

    private val bgExecutor: ExecutorService = ThreadPoolExecutor(
        MAX_BG_CONCURRENCY,
        MAX_BG_CONCURRENCY,
        THREAD_IDLE_TIMEOUT_SEC,
        TimeUnit.SECONDS,
        LinkedBlockingQueue()
    ).apply {
        allowCoreThreadTimeOut(true)
    }

    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }
    private val inFlightFiles = ConcurrentHashMap.newKeySet<String>()
    private val preparingCount = AtomicInteger(0)

    private val chineseTextRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    data class ExtractedBillFields(
        val merchant: String,
        val hasExplicitMerchant: Boolean,
        val amount: Double,
        val category: String,
        val channel: String,
        val account: String,
        val orderId: String,
        val time: String,
        val hasExplicitTime: Boolean,
        val confidence: Double
    )

    fun beginPreparingCapture() {
        preparingCount.incrementAndGet()
    }

    fun endPreparingCapture() {
        preparingCount.updateAndGet { cur -> if (cur > 0) cur - 1 else 0 }
    }

    fun isProcessing(fileName: String): Boolean = inFlightFiles.contains(fileName)

    fun hasInFlightTasks(): Boolean = inFlightFiles.isNotEmpty() || preparingCount.get() > 0

    fun getTaskIdForFile(fileName: String): String {
        val base = fileName.substringBeforeLast(".")
        return "draft-native-$base"
    }

    fun getParsedResultFile(jpgFile: File): File {
        return File(jpgFile.parentFile, "${jpgFile.nameWithoutExtension}.parsed.json")
    }

    /**
     * 将前端 WebView 的 VLM 配置、引擎模式与分类列表同步持久化至原生存储
     * （apiKey 通过 SecureKeyStore 硬件级加密存储）
     */
    fun saveAiConfig(context: Context, configJsonStr: String) {
        try {
            val appCtx = context.applicationContext
            val json = JSONObject(configJsonStr)
            val prefs = appCtx.getSharedPreferences(PREFS_AI, Context.MODE_PRIVATE)
            val editor = prefs.edit()

            if (json.has("provider")) {
                editor.putString(KEY_PROVIDER, json.optString("provider", "openai_chat").trim())
            }
            if (json.has("apiKey")) {
                val rawKey = json.optString("apiKey", "").trim()
                SecureKeyStore.setVlmApiKey(appCtx, rawKey)
            }
            if (json.has("endpoint")) {
                editor.putString(KEY_ENDPOINT, json.optString("endpoint", "").trim())
            }
            if (json.has("model")) {
                editor.putString(KEY_MODEL, json.optString("model", "").trim())
            }
            if (json.has("ocrEngine")) {
                editor.putString(KEY_OCR_ENGINE, json.optString("ocrEngine", "llm").trim())
            }
            if (json.has("categories")) {
                val arr = json.optJSONArray("categories")
                if (arr != null && arr.length() > 0) {
                    editor.putString(KEY_CATEGORIES_JSON, arr.toString())
                }
            }
            if (json.has("autoCommitEnabled")) {
                editor.putBoolean(KEY_AUTO_COMMIT_ENABLED, json.optBoolean("autoCommitEnabled", false))
            }
            if (json.has("autoCommitThreshold")) {
                editor.putInt(KEY_AUTO_COMMIT_THRESHOLD, json.optInt("autoCommitThreshold", 95))
            }
            editor.apply()
            Log.i(
                TAG,
                "Synced AI config to native storage: engine=${prefs.getString(KEY_OCR_ENGINE, "llm")}, " +
                    "provider=${prefs.getString(KEY_PROVIDER, "openai_chat")}, " +
                    "model=${prefs.getString(KEY_MODEL, "")}, " +
                    "hasKey=${SecureKeyStore.getVlmApiKey(appCtx).isNotBlank()}"
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save AI config to native storage: ${e.message}")
        }
    }

    /**
     * 入队后台截图文件并立即在原生后台异步执行 AI / ML Kit 解析
     */
    fun enqueueCapture(context: Context, jpgFile: File) {
        val appContext = context.applicationContext
        val fileName = jpgFile.name
        val parsedFile = getParsedResultFile(jpgFile)

        if (!jpgFile.exists() || parsedFile.exists()) {
            return
        }
        if (!inFlightFiles.add(fileName)) {
            Log.d(TAG, "Capture $fileName is already being processed in background")
            return
        }

        val taskId = getTaskIdForFile(fileName)
        Log.i(TAG, "Enqueued background AI parse for $fileName (taskId=$taskId)")

        LightningAiForegroundService.startIfNeeded(appContext)

        if (MainActivity.isInForeground()) {
            MainActivity.notifyNativeParsingStarted(jpgFile, taskId)
        }

        try {
            bgExecutor.execute {
                var wakeLock: PowerManager.WakeLock? = null
                try {
                    val pm = appContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SingWallet:LightningAiParseLock")?.apply {
                        setReferenceCounted(false)
                        acquire(75_000L)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "WakeLock acquire warning: ${e.message}")
                }

                try {
                    processSingleFile(appContext, jpgFile, taskId)
                } catch (t: Throwable) {
                    Log.e(TAG, "Unhandled error in background parse for $fileName: ${t.message}", t)
                    writeErrorResult(jpgFile, taskId, t.message ?: "后台解析异常")
                } finally {
                    inFlightFiles.remove(fileName)
                    LightningAiForegroundService.stopIfIdle(appContext)
                    try {
                        if (wakeLock?.isHeld == true) {
                            wakeLock.release()
                        }
                    } catch (_: Throwable) {}

                    if (MainActivity.isInForeground()) {
                        MainActivity.onBackgroundParseCompleted(fileName)
                    } else {
                        Log.i(TAG, "Background parse finished for $fileName while app is in background; .parsed.json ready on disk")
                    }
                }
            }
        } catch (t: Throwable) {
            inFlightFiles.remove(fileName)
            LightningAiForegroundService.stopIfIdle(appContext)
            Log.e(TAG, "Failed to schedule background task for $fileName: ${t.message}", t)
        }
    }

    private fun processSingleFile(context: Context, jpgFile: File, taskId: String) {
        if (!jpgFile.exists()) return

        val prefs = context.getSharedPreferences(PREFS_AI, Context.MODE_PRIVATE)
        val ocrEngine = prefs.getString(KEY_OCR_ENGINE, "llm") ?: "llm"
        val provider = prefs.getString(KEY_PROVIDER, "openai_chat") ?: "openai_chat"
        val apiKey = SecureKeyStore.getVlmApiKey(context).trim()
        val rawEndpoint = (prefs.getString(KEY_ENDPOINT, "") ?: "").trim()
        val model = (prefs.getString(KEY_MODEL, "") ?: "").trim()
        val categories = loadCategories(prefs.getString(KEY_CATEGORIES_JSON, null))

        if (ocrEngine == "local") {
            processWithLocalMlKit(context, jpgFile, taskId, categories)
            return
        }

        if (apiKey.isBlank()) {
            Log.w(TAG, "Background VLM skipped: API Key not configured")
            writeErrorResult(jpgFile, taskId, "未配置大模型 API Key")
            showToast(context, "闪电记账：截图已保单入草稿箱（请配置 AI API Key）")
            return
        }

        val effectiveEndpoint = if (rawEndpoint.isNotBlank()) {
            rawEndpoint
        } else {
            when (normalizeProtocol(provider)) {
                "gemini_native" -> "https://generativelanguage.googleapis.com"
                "anthropic_messages" -> "https://api.anthropic.com"
                "openai_chat", "openai_responses" -> "https://api.openai.com"
                else -> ""
            }
        }

        if (effectiveEndpoint.isBlank()) {
            writeErrorResult(jpgFile, taskId, "未配置 Base URL (接口地址为空)，请前往「AI 配置」配置后重试")
            showToast(context, "闪电记账：截图已保单（未配置 AI 接口地址）")
            return
        }

        if (model.isBlank()) {
            writeErrorResult(jpgFile, taskId, "未配置 Model (模型名称为空)，请前往「AI 配置」配置后重试")
            showToast(context, "闪电记账：截图已保单（未配置 AI 模型名称）")
            return
        }

        val imageBytes = jpgFile.readBytes()
        val rawBase64 = Base64.encodeToString(imageBytes, Base64.NO_WRAP)
        val mimeType = if (jpgFile.extension.equals("png", ignoreCase = true)) "image/png" else "image/jpeg"

        val parsedBill = callCloudVlmApi(
            provider = provider,
            apiKey = apiKey,
            rawEndpoint = effectiveEndpoint,
            model = model,
            rawBase64 = rawBase64,
            mimeType = mimeType,
            categories = categories,
            fallbackFileName = jpgFile.name
        )

        writeSuccessResult(jpgFile, taskId, "llm", parsedBill)
        val merchant = parsedBill.optString("merchant", "商户凭证")
        val amount = parsedBill.optDouble("amount", 0.0)
        Log.i(TAG, "Background VLM parse succeeded for ${jpgFile.name}: merchant=$merchant, amount=$amount")
        showToast(context, "闪电记账解析完成：$merchant ¥${String.format(Locale.US, "%.2f", amount)}")
    }

    /**
     * 使用 Google ML Kit 中文离线文字识别引擎解析抓屏账单
     */
    private fun processWithLocalMlKit(
        context: Context,
        jpgFile: File,
        taskId: String,
        categories: List<String>
    ) {
        val inputImage = InputImage.fromFilePath(context, Uri.fromFile(jpgFile))
        val visionText = Tasks.await(
            chineseTextRecognizer.process(inputImage),
            ML_KIT_TIMEOUT_SEC,
            TimeUnit.SECONDS
        )

        val orderedLines = visionText.textBlocks
            .flatMap { it.lines }
            .sortedWith(
                compareBy<com.google.mlkit.vision.text.Text.Line>(
                    { it.boundingBox?.top ?: Int.MAX_VALUE },
                    { it.boundingBox?.left ?: Int.MAX_VALUE }
                )
            )
            .mapNotNull { line -> line.text.trim().takeIf { it.isNotEmpty() } }

        val fallbackLines = if (orderedLines.isEmpty() && visionText.text.isNotBlank()) {
            visionText.text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        } else {
            orderedLines
        }

        if (fallbackLines.isEmpty()) {
            writeErrorResult(jpgFile, taskId, "离线 OCR 未识别出文字内容，请手动核对补录")
            showToast(context, "闪电记账：未识别出账单文字，已保单待核对")
            return
        }

        val fallbackTs = jpgFile.lastModified().takeIf { it > 0L } ?: System.currentTimeMillis()
        val extracted = extractBillFromOcrLines(fallbackLines, categories, fallbackTs)

        if (extracted.amount <= 0.0) {
            Log.w(TAG, "Local ML Kit OCR found no valid amount in ${jpgFile.name}")
            writeErrorResult(jpgFile, taskId, "离线 OCR 未识别到有效金额，请手动核对补充")
            showToast(context, "闪电记账：未识别出有效金额，已存草稿箱待确认")
            return
        }

        val billJson = JSONObject().apply {
            put("merchant", extracted.merchant)
            put("merchantHeader", extracted.merchant.take(8))
            put("amount", extracted.amount)
            put("amountInCents", (extracted.amount * 100.0).roundToInt())
            put("category", extracted.category)
            put("cat", extracted.category)
            put("channel", extracted.channel)
            put("account", extracted.account)
            put("acc", "${extracted.channel} · ${extracted.account}")
            put("orderId", extracted.orderId)
            put("time", extracted.time)
            put("orderTime", extracted.time)
            put("confidence", extracted.confidence)
            put("tag", if (extracted.hasExplicitMerchant) "ML Kit 离线识别" else "离线识别·待确认商户")
            put("rule", "Google ML Kit 中文离线 OCR 规则抽取")
            put("isVlm", false)
        }

        writeSuccessResult(jpgFile, taskId, "local", billJson)
        Log.i(
            TAG,
            "Local ML Kit OCR succeeded for ${jpgFile.name}: merchant=${extracted.merchant}, " +
                "amount=${extracted.amount}, confidence=${extracted.confidence}"
        )
        showToast(
            context,
            "闪电记账已完成离线识别：${extracted.merchant} ¥${String.format(Locale.US, "%.2f", extracted.amount)}"
        )
    }

    /**
     * 纯 Kotlin 账单规则抽取引擎：从有序 OCR 文本行中抽取金额、商户、渠道、卡号/账户、时间与单号
     */
    internal fun extractBillFromOcrLines(
        lines: List<String>,
        categories: List<String> = DEFAULT_CATEGORIES,
        fallbackTimestampMs: Long = System.currentTimeMillis()
    ): ExtractedBillFields {
        val fullText = lines.joinToString("\n")

        val amount = extractAmountFromOcr(lines)
        val channel = extractChannelFromOcr(fullText)
        val account = extractAccountFromOcr(lines, channel)
        val (timeStr, hasExplicitTime) = extractTimeFromOcr(fullText, fallbackTimestampMs)
        val orderId = extractOrderIdFromOcr(lines)
        val (merchant, hasExplicitMerchant) = extractMerchantFromOcr(lines)
        val category = inferCategory(merchant, fullText, categories)

        val confidence = if (amount <= 0.0 || !hasExplicitMerchant) {
            0.0
        } else {
            var score = 76.0
            if (orderId.isNotEmpty() && !orderId.startsWith("LOCAL_")) score += 8.0
            if (hasExplicitTime) score += 5.0
            if (channel != "微信" || fullText.contains("微信")) score += 4.0
            if (account.contains("(") || account in setOf("零钱通", "零钱", "花呗", "余额宝", "余额")) score += 2.0
            score.coerceIn(0.0, 95.0)
        }

        return ExtractedBillFields(
            merchant = merchant,
            hasExplicitMerchant = hasExplicitMerchant,
            amount = amount,
            category = category,
            channel = channel,
            account = account,
            orderId = orderId.ifEmpty { "LOCAL_$fallbackTimestampMs" },
            time = timeStr,
            hasExplicitTime = hasExplicitTime,
            confidence = confidence
        )
    }

    private fun extractAmountFromOcr(lines: List<String>): Double {
        val labeledPattern = Regex(
            "(?:实付(?:金额)?|付款(?:金额)?|支付(?:金额)?|消费金额|合计|总计|交易金额|金额)\\s*[:：]?\\s*-?\\s*[¥￥]?\\s*(\\d{1,7}(?:,\\d{3})*(?:\\.\\d{1,2})?)"
        )
        val currencySymbolPattern = Regex("-?\\s*[¥￥]\\s*(\\d{1,7}(?:,\\d{3})*(?:\\.\\d{1,2})?)")
        val signedDecimalPattern = Regex("^-\\s*(\\d{1,7}(?:,\\d{3})*\\.\\d{2})$")
        val standaloneDecimalPattern = Regex("^(\\d{1,7}\\.\\d{2})(?:\\s*元)?$")

        val skipLineKeywords = listOf("单号", "卡号", "尾号", "积分", "优惠", "折扣", "立减", "余额", "手续费", "原价", "电话", "时间")

        for (line in lines) {
            val match = labeledPattern.find(line)
            if (match != null) {
                val valNum = match.groupValues[1].replace(",", "").toDoubleOrNull()
                if (valNum != null && valNum > 0.0 && valNum < 1_000_000.0) {
                    return (valNum * 100.0).roundToInt() / 100.0
                }
            }
        }

        for (line in lines) {
            if (skipLineKeywords.any { line.contains(it) }) continue
            val match = currencySymbolPattern.find(line) ?: signedDecimalPattern.find(line.trim())
            if (match != null) {
                val valNum = match.groupValues[1].replace(",", "").toDoubleOrNull()
                if (valNum != null && valNum > 0.0 && valNum < 1_000_000.0) {
                    return (valNum * 100.0).roundToInt() / 100.0
                }
            }
        }

        for (line in lines) {
            if (skipLineKeywords.any { line.contains(it) }) continue
            val match = standaloneDecimalPattern.find(line.trim())
            if (match != null) {
                val valNum = match.groupValues[1].toDoubleOrNull()
                if (valNum != null && valNum > 0.0 && valNum < 1_000_000.0) {
                    return (valNum * 100.0).roundToInt() / 100.0
                }
            }
        }

        return 0.0
    }

    private fun extractChannelFromOcr(fullText: String): String {
        return when {
            fullText.contains("支付宝") || fullText.contains("花呗") || fullText.contains("余额宝") -> "支付宝"
            fullText.contains("云闪付") || fullText.contains("银联") -> "云闪付"
            fullText.contains("现金") -> "现金"
            else -> "微信"
        }
    }

    private fun extractAccountFromOcr(lines: List<String>, channel: String): String {
        val bankNames = listOf(
            "工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行",
            "邮储银行", "邮政储蓄银行", "浦发银行", "兴业银行", "民生银行", "光大银行",
            "平安银行", "中信银行", "广发银行", "华夏银行", "北京银行", "上海银行", "宁波银行"
        )
        val fullText = lines.joinToString("\n")
        for (line in lines) {
            val matchedBank = bankNames.firstOrNull { line.contains(it) }
            if (matchedBank != null) {
                val normBank = matchedBank.removePrefix("中国")
                val digitsMatch = Regex("(?:尾号\\s*|[(（\\[])(\\d{4})[)）\\]]?|(\\d{4})(?=\\s*$)").find(line)
                val last4 = digitsMatch?.groupValues?.drop(1)?.firstOrNull { it.isNotEmpty() }
                return if (last4 != null) "$normBank($last4)" else normBank
            }
        }

        val cardTailPattern = Regex("(?:储蓄卡|借记卡|信用卡)\\s*[(（\\[]?(\\d{4})[)）\\]]?")
        for (line in lines) {
            val m = cardTailPattern.find(line)
            if (m != null) {
                return "银行卡(${m.groupValues[1]})"
            }
        }

        return when {
            fullText.contains("零钱通") -> "零钱通"
            fullText.contains("零钱") -> "零钱"
            fullText.contains("花呗") -> "花呗"
            fullText.contains("余额宝") -> "余额宝"
            fullText.contains("余额") && channel == "支付宝" -> "余额"
            channel == "支付宝" -> "余额"
            channel == "云闪付" -> "银行卡"
            channel == "现金" -> "现金钱包"
            else -> "钱包"
        }
    }

    private fun extractTimeFromOcr(fullText: String, fallbackTimestampMs: Long): Pair<String, Boolean> {
        val fullDateTimeRegex = Regex(
            "(\\d{4})[-/.年](\\d{1,2})[-/.月](\\d{1,2})日?\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?"
        )
        val mFull = fullDateTimeRegex.find(fullText)
        if (mFull != null) {
            val y = mFull.groupValues[1]
            val mo = mFull.groupValues[2].padStart(2, '0')
            val d = mFull.groupValues[3].padStart(2, '0')
            val h = mFull.groupValues[4].padStart(2, '0')
            val mi = mFull.groupValues[5].padStart(2, '0')
            val s = mFull.groupValues[6].ifEmpty { "00" }.padStart(2, '0')
            return Pair("$y-$mo-$d $h:$mi:$s", true)
        }

        val shortDateTimeRegex = Regex(
            "(\\d{1,2})[-/月](\\d{1,2})日?\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?"
        )
        val mShort = shortDateTimeRegex.find(fullText)
        if (mShort != null) {
            val year = SimpleDateFormat("yyyy", Locale.US).format(Date(fallbackTimestampMs))
            val mo = mShort.groupValues[1].padStart(2, '0')
            val d = mShort.groupValues[2].padStart(2, '0')
            val h = mShort.groupValues[3].padStart(2, '0')
            val mi = mShort.groupValues[4].padStart(2, '0')
            val s = mShort.groupValues[5].ifEmpty { "00" }.padStart(2, '0')
            return Pair("$year-$mo-$d $h:$mi:$s", true)
        }

        val fallbackStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(fallbackTimestampMs))
        return Pair(fallbackStr, false)
    }

    private fun extractOrderIdFromOcr(lines: List<String>): String {
        val labeledOrderRegex = Regex(
            "(?:交易单号|订单号|商户单号|流水号|转账单号|平台单号)\\s*[:：]?\\s*([A-Za-z0-9]{10,40})"
        )
        for (i in lines.indices) {
            val line = lines[i]
            val m = labeledOrderRegex.find(line)
            if (m != null) {
                return m.groupValues[1]
            }
            if (line.contains("单号") || line.contains("流水号")) {
                val nextLine = lines.getOrNull(i + 1)?.trim().orEmpty()
                if (Regex("^[A-Za-z0-9]{10,40}$").matches(nextLine)) {
                    return nextLine
                }
            }
        }

        val longNumericRegex = Regex("\\b(\\d{16,32})\\b")
        for (line in lines) {
            val m = longNumericRegex.find(line)
            if (m != null) {
                return m.groupValues[1]
            }
        }
        return ""
    }

    private fun extractMerchantFromOcr(lines: List<String>): Pair<String, Boolean> {
        val labeledMerchantRegex = Regex(
            "^(?:收款方|商户全称|商户名称|商品说明|交易对象|对方账户|店铺名称?)\\s*[:：]?\\s*(.+)$"
        )
        for (i in lines.indices) {
            val line = lines[i].trim()
            val m = labeledMerchantRegex.find(line)
            if (m != null) {
                val candidate = m.groupValues[1].trim()
                if (isPlausibleMerchant(candidate)) {
                    return Pair(candidate.take(40), true)
                }
                val nextLine = lines.getOrNull(i + 1)?.trim().orEmpty()
                if (isPlausibleMerchant(nextLine)) {
                    return Pair(nextLine.take(40), true)
                }
            }
        }

        val amountLineIdx = lines.indexOfFirst {
            Regex("^[+-]?\\s*[¥￥]\\s*\\d+(?:\\.\\d{1,2})?$").matches(it.trim()) ||
                Regex("^[+-]?\\d+\\.\\d{2}$").matches(it.trim())
        }
        if (amountLineIdx > 0) {
            for (idx in (amountLineIdx - 1) downTo 0) {
                val candidate = lines[idx].trim()
                if (isPlausibleMerchant(candidate)) {
                    return Pair(candidate.take(40), true)
                }
            }
        }

        for (line in lines) {
            val candidate = line.trim()
            if (isPlausibleMerchant(candidate)) {
                return Pair(candidate.take(40), true)
            }
        }

        return Pair("未知商户（请确认）", false)
    }

    private fun isPlausibleMerchant(text: String): Boolean {
        if (text.length < 2 || text.length > 48) return false
        if (Regex("^[+-]?\\s*[¥￥]?\\s*\\d+(?:[.,]\\d+)*$").matches(text)) return false
        if (Regex("^\\d{1,2}:\\d{2}(?::\\d{2})?$").matches(text)) return false
        if (Regex("^\\d{4}[-/.年]\\d{1,2}[-/.月]\\d{1,2}.*").matches(text)) return false
        if (Regex("^[A-Za-z0-9]{12,}$").matches(text)) return false

        val noiseExact = setOf(
            "账单详情", "支付成功", "付款成功", "交易成功", "已支付", "全部账单",
            "当前状态", "支付时间", "付款时间", "交易时间", "支付方式", "付款方式",
            "交易单号", "商户单号", "订单号", "商品", "收款方", "商户全称",
            "联系客服", "对此订单有疑问", "查看往来记录", "电子回单", "发票助手",
            "微信支付", "支付宝", "云闪付", "账单"
        )
        if (text in noiseExact) return false
        if (text.contains("有疑问") || text.contains("已完成") || text.contains("全部服务")) return false
        return true
    }

    private fun inferCategory(merchant: String, fullText: String, categories: List<String>): String {
        val target = "$merchant $fullText"
        val mapping = listOf(
            listOf("外卖", "餐饮", "餐厅", "饭店", "火锅", "烧烤", "咖啡", "奶茶", "星巴克", "瑞幸", "肯德基", "麦当劳", "蜜雪", "喜茶", "霸王茶姬", "面包", "早餐", "午餐", "晚餐") to "餐饮美食",
            listOf("滴滴", "打车", "出租车", "网约车", "地铁", "公交", "高铁", "火车", "机票", "航空", "加油", "中石化", "中石油", "高速", "停车", "单车", "哈啰", "青桔") to "交通出行",
            listOf("水费", "电费", "燃气", "煤气", "物业", "宽带", "话费", "充值", "国家电网", "联通", "移动", "电信") to "生活缴费",
            listOf("药房", "药店", "医院", "诊所", "体检", "挂号", "医疗", "口腔", "眼科") to "医疗健康",
            listOf("电影", "影院", "门票", "旅游", "酒店", "民宿", "游戏", "会员", "视频", "音乐", "KTV") to "休闲娱乐",
            listOf("超市", "便利店", "全家", "罗森", "7-11", "711", "盒马", "山姆", "京东", "淘宝", "天猫", "拼多多", "美团优选", "百货", "商场") to "日常购物",
            listOf("工资", "薪资", "奖金", "发薪") to "工资收入"
        )
        for ((keywords, cat) in mapping) {
            if (categories.contains(cat) && keywords.any { target.contains(it, ignoreCase = true) }) {
                return cat
            }
        }
        return when {
            categories.contains("日常购物") -> "日常购物"
            categories.contains("其他支出") -> "其他支出"
            else -> categories.firstOrNull() ?: "其他支出"
        }
    }

    private fun writeSuccessResult(jpgFile: File, taskId: String, engine: String, billObj: JSONObject) {
        try {
            val parsedFile = getParsedResultFile(jpgFile)
            val tempFile = File(jpgFile.parentFile, "${jpgFile.nameWithoutExtension}.parsed.tmp")
            val wrapper = JSONObject().apply {
                put("status", "ok")
                put("taskId", taskId)
                put("engine", engine)
                put("fileName", jpgFile.name)
                put("completedAt", System.currentTimeMillis())
                put("result", billObj)
            }
            tempFile.writeText(wrapper.toString(), Charsets.UTF_8)
            if (parsedFile.exists()) parsedFile.delete()
            tempFile.renameTo(parsedFile)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write success result for ${jpgFile.name}: ${e.message}", e)
        }
    }

    private fun writeErrorResult(jpgFile: File, taskId: String, errorReason: String) {
        try {
            val parsedFile = getParsedResultFile(jpgFile)
            val tempFile = File(jpgFile.parentFile, "${jpgFile.nameWithoutExtension}.parsed.tmp")
            val wrapper = JSONObject().apply {
                put("status", "error")
                put("taskId", taskId)
                put("fileName", jpgFile.name)
                put("completedAt", System.currentTimeMillis())
                put("errorReason", errorReason)
            }
            tempFile.writeText(wrapper.toString(), Charsets.UTF_8)
            if (parsedFile.exists()) parsedFile.delete()
            tempFile.renameTo(parsedFile)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write error result for ${jpgFile.name}: ${e.message}", e)
        }
    }

    private fun loadCategories(categoriesJson: String?): List<String> {
        if (!categoriesJson.isNullOrBlank()) {
            try {
                val arr = JSONArray(categoriesJson)
                val list = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val item = arr.optString(i).trim()
                    if (item.isNotEmpty()) list.add(item)
                }
                if (list.isNotEmpty()) return list
            } catch (_: Exception) {}
        }
        return DEFAULT_CATEGORIES
    }

    private fun buildVlmPromptText(categories: List<String>): String {
        val catListStr = categories.joinToString("、")
        return "你是一个高精度智能账单识别专家。请提取图片中的账单信息，必须且仅返回如下严格的 JSON 对象：" +
            "{\"merchant\": \"商户全称\", \"amount\": 金额数字如26.80, \"category\": \"标准分类(${categories.size}选一)\", " +
            "\"time\": \"交易时间如2026-10-26 12:00:00\", \"orderId\": \"交易单号\", \"channel\": \"微信支付或支付宝\", \"account\": \"支出账户\"}。" +
            "极其重要规则：1. category 字段必须严格且只能在以下标准分类中选择最匹配的一个（严禁自行创造词汇）：$catListStr。" +
            "2. account 字段为支付方式中的具体扣款账户：微信默认为“钱包”（或“零钱通”），支付宝默认为“余额”（或“余额宝”/“花呗”）；" +
            "若是银行卡，必须剔除“中国”、“银联”、“储蓄卡”、“借记卡”、“信用卡”等卡种修饰词并保留卡号，" +
            "如“工商银行银联储蓄卡[5678]”输出为“工商银行[5678]”，“中国工商银行储蓄卡(5678)”输出为“工商银行(5678)”。"
    }

    fun getBaseOriginPath(rawUrl: String): String {
        var u = rawUrl.trim()
        if (u.isEmpty()) return ""

        val hashIdx = u.indexOf('#')
        if (hashIdx != -1) u = u.substring(0, hashIdx).trim()
        val qIdx = u.indexOf('?')
        if (qIdx != -1) u = u.substring(0, qIdx).trim()
        u = u.trimEnd('/')

        if (!u.startsWith("http://", ignoreCase = true) &&
            !u.startsWith("https://", ignoreCase = true) &&
            !u.startsWith("mock-") &&
            !u.startsWith("test-")
        ) {
            val isLocal = Regex("^(?:localhost|127\\.0\\.0\\.1|192\\.168\\.|10\\.|172\\.(?:1[6-9]|2\\d|3[01])\\.)", RegexOption.IGNORE_CASE).containsMatchIn(u)
            u = if (isLocal) "http://$u" else "https://$u"
        }

        val suffixPatterns = listOf(
            Regex("/v1(?:beta\\d*)?/chat(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/chat/completions?(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/v1(?:beta\\d*)?/messages?(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/messages?(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/v1(?:beta\\d*)?/responses?(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/responses?(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/v1(?:beta\\d*)?/models(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/models/[^/]+:generateContent(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/models(?:/)?$", RegexOption.IGNORE_CASE),
            Regex(":generateContent(?:/.*)?$", RegexOption.IGNORE_CASE),
            Regex("/v1beta\\d*(?:/)?$", RegexOption.IGNORE_CASE),
            Regex("/v1(?:/)?$", RegexOption.IGNORE_CASE)
        )

        var changed: Boolean
        do {
            changed = false
            u = u.trimEnd('/')
            for (pattern in suffixPatterns) {
                if (pattern.containsMatchIn(u)) {
                    u = pattern.replace(u, "").trimEnd('/')
                    changed = true
                    break
                }
            }
        } while (changed)

        u = u.trimEnd('/')
        if (u.endsWith("open.bigmodel.cn/api/paas", ignoreCase = true)) {
            u += "/v4"
        }
        return u
    }

    fun normalizeProtocol(protocol: String?): String {
        val p = (protocol ?: "openai_chat").trim().lowercase(Locale.ROOT)
        return when (p) {
            "openai", "qwen", "custom", "zhipu", "glm", "openai_chat" -> "openai_chat"
            "gemini", "gemini_native" -> "gemini_native"
            "anthropic", "claude", "anthropic_messages" -> "anthropic_messages"
            "responses", "openai_responses" -> "openai_responses"
            else -> "openai_chat"
        }
    }

    fun normalizeApiEndpoint(rawEndpoint: String, protocol: String?, model: String?): String {
        if (rawEndpoint.isBlank()) return ""
        var extractedModel = (model ?: "").trim()
        if (extractedModel.isEmpty()) {
            val match = Regex("/models/([^/:]+):generateContent", RegexOption.IGNORE_CASE).find(rawEndpoint)
            if (match != null) extractedModel = match.groupValues[1]
        }
        val base = getBaseOriginPath(rawEndpoint)
        if (base.isEmpty()) return ""

        val hasExplicitVersion = Regex("/v\\d+(?:beta\\d*)?$", RegexOption.IGNORE_CASE).containsMatchIn(base) ||
            Regex("/api/paas/v\\d+", RegexOption.IGNORE_CASE).containsMatchIn(base)

        return when (normalizeProtocol(protocol)) {
            "openai_chat" -> if (hasExplicitVersion) "$base/chat/completions" else "$base/v1/chat/completions"
            "anthropic_messages" -> if (hasExplicitVersion) "$base/messages" else "$base/v1/messages"
            "openai_responses" -> if (hasExplicitVersion) "$base/responses" else "$base/v1/responses"
            "gemini_native" -> {
                val m = extractedModel.ifEmpty { "gemini-1.5-flash" }
                if (hasExplicitVersion) "$base/models/$m:generateContent" else "$base/v1beta/models/$m:generateContent"
            }
            else -> if (hasExplicitVersion) "$base/chat/completions" else "$base/v1/chat/completions"
        }
    }

    private fun callCloudVlmApi(
        provider: String,
        apiKey: String,
        rawEndpoint: String,
        model: String,
        rawBase64: String,
        mimeType: String,
        categories: List<String>,
        fallbackFileName: String
    ): JSONObject {
        val proto = normalizeProtocol(provider)
        val targetEndpoint = normalizeApiEndpoint(rawEndpoint, proto, model)
        val promptText = buildVlmPromptText(categories)
        val dataUrl = "data:$mimeType;base64,$rawBase64"
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(TOTAL_HTTP_DEADLINE_MS)

        when (proto) {
            "gemini_native" -> {
                // 仅通过 x-goog-api-key 请求头传递密钥，严禁拼接 URL ?key=
                val headers = mapOf(
                    "Content-Type" to "application/json",
                    "x-goog-api-key" to apiKey
                )
                val schemaPayload = JSONObject().apply {
                    put("contents", JSONArray().put(JSONObject().apply {
                        put("role", "user")
                        put("parts", JSONArray()
                            .put(JSONObject().put("text", promptText))
                            .put(JSONObject().put("inlineData", JSONObject().apply {
                                put("mimeType", mimeType)
                                put("data", rawBase64)
                            }))
                        )
                    }))
                    put("generationConfig", JSONObject().apply {
                        put("responseMimeType", "application/json")
                    })
                }
                val (code, bodyStr) = executeHttpPost(targetEndpoint, headers, schemaPayload.toString(), deadlineNanos)
                val respJson = try { JSONObject(bodyStr) } catch (_: Exception) { null }
                if (code !in 200..299 || respJson?.has("error") == true) {
                    val errMsg = respJson?.optJSONObject("error")?.optString("message") ?: "HTTP $code"
                    throw IllegalStateException("Gemini 接口调用失败: $errMsg")
                }
                val text = respJson?.optJSONArray("candidates")
                    ?.optJSONObject(0)
                    ?.optJSONObject("content")
                    ?.optJSONArray("parts")
                    ?.optJSONObject(0)
                    ?.optString("text")
                    ?: respJson?.optJSONArray("choices")
                        ?.optJSONObject(0)
                        ?.optJSONObject("message")
                        ?.optString("content")
                    ?: ""
                val extracted = extractJsonFromVlmResponse(text)
                    ?: throw IllegalStateException("未能从 Gemini 响应中解析出 JSON 数据")
                return normalizeExtractedBill(extracted, categories, fallbackFileName)
            }

            "anthropic_messages" -> {
                val headers = mapOf(
                    "Content-Type" to "application/json",
                    "x-api-key" to apiKey,
                    "Authorization" to "Bearer $apiKey",
                    "anthropic-version" to "2023-06-01"
                )
                val payload = JSONObject().apply {
                    put("model", model)
                    put("max_tokens", 1024)
                    put("messages", JSONArray().put(JSONObject().apply {
                        put("role", "user")
                        put("content", JSONArray()
                            .put(JSONObject().apply {
                                put("type", "image")
                                put("source", JSONObject().apply {
                                    put("type", "base64")
                                    put("media_type", mimeType)
                                    put("data", rawBase64)
                                })
                            })
                            .put(JSONObject().apply {
                                put("type", "text")
                                put("text", promptText)
                            })
                        )
                    }))
                }
                val (code, bodyStr) = executeHttpPost(targetEndpoint, headers, payload.toString(), deadlineNanos)
                val respJson = try { JSONObject(bodyStr) } catch (_: Exception) { null }
                if (code !in 200..299 || respJson?.has("error") == true) {
                    val errMsg = respJson?.optJSONObject("error")?.optString("message") ?: "HTTP $code"
                    throw IllegalStateException("Anthropic 接口调用失败: $errMsg")
                }
                val text = respJson?.optJSONArray("content")
                    ?.optJSONObject(0)
                    ?.optString("text")
                    ?: respJson?.optJSONArray("choices")
                        ?.optJSONObject(0)
                        ?.optJSONObject("message")
                        ?.optString("content")
                    ?: ""
                val extracted = extractJsonFromVlmResponse(text)
                    ?: throw IllegalStateException("未能从 Anthropic 响应中解析出 JSON 数据")
                return normalizeExtractedBill(extracted, categories, fallbackFileName)
            }

            "openai_responses" -> {
                val headers = mapOf(
                    "Content-Type" to "application/json",
                    "Authorization" to "Bearer $apiKey"
                )
                val payload = JSONObject().apply {
                    put("model", model)
                    put("input", JSONArray().put(JSONObject().apply {
                        put("role", "user")
                        put("content", JSONArray()
                            .put(JSONObject().apply {
                                put("type", "input_text")
                                put("text", promptText)
                            })
                            .put(JSONObject().apply {
                                put("type", "input_image")
                                put("image_url", dataUrl)
                            })
                        )
                    }))
                }
                val (code, bodyStr) = executeHttpPost(targetEndpoint, headers, payload.toString(), deadlineNanos)
                val respJson = try { JSONObject(bodyStr) } catch (_: Exception) { null }
                if (code !in 200..299 || respJson?.has("error") == true) {
                    val errMsg = respJson?.optJSONObject("error")?.optString("message") ?: "HTTP $code"
                    throw IllegalStateException("Responses API 接口调用失败: $errMsg")
                }
                val text = respJson?.optString("output_text")?.takeIf { it.isNotBlank() }
                    ?: respJson?.optJSONArray("output")
                        ?.optJSONObject(0)
                        ?.optJSONArray("content")
                        ?.optJSONObject(0)
                        ?.optString("text")
                    ?: respJson?.optJSONArray("choices")
                        ?.optJSONObject(0)
                        ?.optJSONObject("message")
                        ?.optString("content")
                    ?: ""
                val extracted = extractJsonFromVlmResponse(text)
                    ?: throw IllegalStateException("未能从 Responses API 返回中解析出 JSON 数据")
                return normalizeExtractedBill(extracted, categories, fallbackFileName)
            }

            else -> {
                val headers = mapOf(
                    "Content-Type" to "application/json",
                    "Authorization" to "Bearer $apiKey"
                )
                val messagesArr = JSONArray().put(JSONObject().apply {
                    put("role", "user")
                    put("content", JSONArray()
                        .put(JSONObject().apply {
                            put("type", "text")
                            put("text", promptText)
                        })
                        .put(JSONObject().apply {
                            put("type", "image_url")
                            put("image_url", JSONObject().put("url", dataUrl))
                        })
                    )
                })

                val jsonObjectPayload = JSONObject().apply {
                    put("model", model)
                    put("messages", messagesArr)
                    put("temperature", 0.1)
                    put("max_tokens", 512)
                    put("response_format", JSONObject().put("type", "json_object"))
                }

                var (code, bodyStr) = executeHttpPost(targetEndpoint, headers, jsonObjectPayload.toString(), deadlineNanos)
                var respJson = try { JSONObject(bodyStr) } catch (_: Exception) { null }

                if (code !in 200..299 &&
                    (code == 400 || code == 422 || bodyStr.contains("response_format", ignoreCase = true)) &&
                    remainingMillis(deadlineNanos) > 5_000L
                ) {
                    val plainPayload = JSONObject().apply {
                        put("model", model)
                        put("messages", messagesArr)
                        put("temperature", 0.1)
                        put("max_tokens", 512)
                    }
                    val retryRes = executeHttpPost(targetEndpoint, headers, plainPayload.toString(), deadlineNanos)
                    code = retryRes.first
                    bodyStr = retryRes.second
                    respJson = try { JSONObject(bodyStr) } catch (_: Exception) { null }
                }

                if (code !in 200..299 || respJson?.has("error") == true) {
                    val errMsg = respJson?.optJSONObject("error")?.optString("message") ?: "HTTP $code"
                    throw IllegalStateException("大模型接口调用失败: $errMsg")
                }

                val text = respJson?.optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content")
                    ?: ""
                val extracted = extractJsonFromVlmResponse(text)
                    ?: throw IllegalStateException("未能从大模型返回中解析到结构化 JSON 数据")
                return normalizeExtractedBill(extracted, categories, fallbackFileName)
            }
        }
    }

    private fun remainingMillis(deadlineNanos: Long): Long {
        return TimeUnit.NANOSECONDS.toMillis(deadlineNanos - System.nanoTime()).coerceAtLeast(0L)
    }

    private fun executeHttpPost(
        urlStr: String,
        headers: Map<String, String>,
        jsonBody: String,
        deadlineNanos: Long
    ): Pair<Int, String> {
        val bodyBytes = jsonBody.toByteArray(Charsets.UTF_8)
        val maxAttempts = 3
        var lastException: Throwable? = null
        for (attempt in 1..maxAttempts) {
            val remBefore = remainingMillis(deadlineNanos)
            if (remBefore < 2_000L) {
                break
            }
            var conn: HttpURLConnection? = null
            try {
                val url = URL(urlStr)
                val connTimeout = minOf(10_000, remBefore.toInt()).coerceAtLeast(1_000)
                val readTimeoutVal = minOf(25_000, remBefore.toInt()).coerceAtLeast(2_000)
                conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = connTimeout
                    readTimeout = readTimeoutVal
                    doInput = true
                    doOutput = true
                    useCaches = false
                    setFixedLengthStreamingMode(bodyBytes.size)
                    for ((k, v) in headers) {
                        setRequestProperty(k, v)
                    }
                }
                conn.outputStream.use { os ->
                    os.write(bodyBytes)
                    os.flush()
                }
                val statusCode = conn.responseCode
                val stream = if (statusCode in 200..299) conn.inputStream else (conn.errorStream ?: conn.inputStream)
                val responseText = if (stream != null) {
                    BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
                } else {
                    ""
                }
                if (statusCode in listOf(429, 502, 503, 504) && attempt < maxAttempts) {
                    val backoffMs = 800L * attempt
                    if (remainingMillis(deadlineNanos) > backoffMs + 3_000L) {
                        Log.w(TAG, "Transient HTTP $statusCode on attempt $attempt/$maxAttempts, retrying after ${backoffMs}ms...")
                        Thread.sleep(backoffMs)
                        continue
                    }
                }
                return Pair(statusCode, responseText)
            } catch (e: Throwable) {
                lastException = e
                Log.w(TAG, "HTTP POST network error on attempt $attempt/$maxAttempts: ${e.message}")
                if (attempt < maxAttempts) {
                    val backoffMs = 800L * attempt
                    if (remainingMillis(deadlineNanos) > backoffMs + 3_000L) {
                        try {
                            Thread.sleep(backoffMs)
                        } catch (_: InterruptedException) {
                            break
                        }
                    } else {
                        break
                    }
                }
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Throwable) {}
            }
        }
        throw lastException ?: IllegalStateException("网络请求超时或失败")
    }

    fun extractJsonFromVlmResponse(rawText: String?): JSONObject? {
        if (rawText.isNullOrBlank()) return null
        val cleaned = rawText
            .replace(Regex("<think>[\\s\\S]*?</think>", RegexOption.IGNORE_CASE), "")
            .replace(Regex("<think>[\\s\\S]*$", RegexOption.IGNORE_CASE), "")
            .replace(Regex("```(?:json)?", RegexOption.IGNORE_CASE), "")
            .replace("```", "")
            .trim()
        if (cleaned.isEmpty()) return null

        val firstBrace = cleaned.indexOf('{')
        val lastBrace = cleaned.lastIndexOf('}')
        if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
            return null
        }
        val candidate = cleaned.substring(firstBrace, lastBrace + 1)
        return try {
            JSONObject(candidate)
        } catch (_: Exception) {
            val sanitized = candidate
                .replace(Regex(",\\s*([}\\]])"), "$1")
                .replace(Regex("[\\u0000-\\u0019]+"), " ")
            try {
                JSONObject(sanitized)
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun normalizeExtractedBill(
        parsed: JSONObject,
        categories: List<String>,
        fallbackFileName: String
    ): JSONObject {
        val rawAmtStr = parsed.opt("amount")?.toString()?.replace(Regex("[¥￥$€£,\\s]"), "") ?: "0"
        val parsedFloat = rawAmtStr.toDoubleOrNull() ?: 0.0
        val amount = if (parsedFloat.isFinite()) (abs(parsedFloat) * 100.0).roundToInt() / 100.0 else 0.0

        val rawMerchant = listOf("merchant", "merchantName", "merchant_header", "title")
            .map { parsed.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() && it != "null" }
        val hasValidMerchant = !rawMerchant.isNullOrBlank()
        val extractedMerchant = rawMerchant ?: fallbackFileName.substringBeforeLast(".").ifEmpty { "商户凭证" }

        val rawCategory = parsed.optString("category", "").trim()
        val defaultCat = if (categories.contains("日常购物")) "日常购物" else (categories.firstOrNull() ?: "日常购物")
        val resolvedCat = if (categories.contains(rawCategory)) rawCategory else defaultCat

        val rawChannel = listOf("channel", "payment_channel")
            .map { parsed.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: parsed.optJSONObject("payment")?.optString("channel", "")?.trim()?.takeIf { it.isNotEmpty() }
            ?: "微信"

        val normChannel = when {
            rawChannel.contains("支付宝") -> "支付宝"
            rawChannel.contains("云闪付") || rawChannel.contains("银联") -> "云闪付"
            rawChannel.contains("现金") -> "现金"
            else -> "微信"
        }

        val rawAccount = listOf("account", "payment_account", "pay_account", "sub_type", "card")
            .map { parsed.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: parsed.optJSONObject("payment")?.optString("sub_type", "")?.trim()?.takeIf { it.isNotEmpty() }
            ?: when (normChannel) {
                "支付宝" -> "余额"
                "云闪付" -> "银行卡"
                "现金" -> "现金钱包"
                else -> "钱包"
            }

        val extractedOrderId = listOf("orderId", "order_id", "orderNo")
            .map { parsed.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() && it != "null" }
        val orderId = extractedOrderId ?: "VLM_${System.currentTimeMillis()}"

        val nowStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val extractedTime = listOf("time", "orderTime", "order_time")
            .map { parsed.optString(it, "").trim() }
            .firstOrNull { it.isNotEmpty() && it != "null" }
        val timeStr = extractedTime ?: nowStr

        // 动态计算置信度：若金额 <= 0 或无有效商户，强制 confidence = 0.0 禁止自动入账
        val confidence = if (amount <= 0.0 || !hasValidMerchant) {
            0.0
        } else {
            var score = 91.0
            if (extractedOrderId != null) score += 4.0
            if (extractedTime != null) score += 2.5
            if (categories.contains(rawCategory)) score += 1.5
            score.coerceIn(0.0, 99.0)
        }

        return JSONObject().apply {
            put("merchant", extractedMerchant)
            put("merchantHeader", extractedMerchant.take(8))
            put("amount", amount)
            put("amountInCents", (amount * 100).roundToInt())
            put("category", resolvedCat)
            put("cat", resolvedCat)
            put("channel", normChannel)
            put("account", rawAccount)
            put("acc", "$normChannel · $rawAccount")
            put("orderId", orderId)
            put("time", timeStr)
            put("orderTime", timeStr)
            put("confidence", confidence)
            put("tag", if (confidence > 0.0) "大模型 VLM 高精识别" else "识别不完整·请核对")
            put("rule", "VLM 视觉智能识别")
            put("isVlm", true)
        }
    }

    private fun showToast(context: Context, message: String) {
        mainHandler.post {
            try {
                Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Log.w(TAG, "showToast error: ${e.message}")
            }
        }
    }
}
