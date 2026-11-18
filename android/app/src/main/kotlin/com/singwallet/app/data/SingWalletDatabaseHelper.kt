package com.singwallet.app.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * SingWallet 统一原生 SQLite 持久化引擎.
 *
 * 严格对齐 `docs/跨平台架构与数据规范.md` §3 的 12 张核心业务表与全部 11 个索引，
 * 并提供 `app_kv_store` 桥接键值存储与事务化流水投影能力。
 * 开启 WAL 日志模式与外键约束。
 */
class SingWalletDatabaseHelper private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val TAG = "SingWalletDB"
        private const val DATABASE_NAME = "singwallet.db"
        private const val DATABASE_VERSION = 1
        private const val KEY_USER_TRANSACTIONS = "user_transactions"

        private val DEFAULT_CORE_CATEGORIES = listOf(
            Triple("cat_canyin", "餐饮美食", "expense"),
            Triple("cat_jiaotong", "交通出行", "expense"),
            Triple("cat_gouwu", "日常购物", "expense"),
            Triple("cat_yule", "休闲娱乐", "expense"),
            Triple("cat_jiaofei", "生活缴费", "expense"),
            Triple("cat_yiliao", "医疗健康", "expense"),
            Triple("cat_qita", "其他支出", "expense"),
            Triple("cat_gongzi", "工资收入", "income")
        )

        @Volatile
        private var instance: SingWalletDatabaseHelper? = null

        fun getInstance(context: Context): SingWalletDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: SingWalletDatabaseHelper(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val writeLock = Any()

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        // 1. 导入任务流水表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS capture_jobs (
                id TEXT PRIMARY KEY NOT NULL,
                content_hash TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                imported_at TEXT NOT NULL,
                private_image_ref TEXT NOT NULL,
                state TEXT NOT NULL,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                parser_version INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_capture_jobs_hash ON capture_jobs(content_hash)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_capture_jobs_state ON capture_jobs(state)")

        // 2. 识别草稿表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS drafts (
                id TEXT PRIMARY KEY NOT NULL,
                capture_id TEXT NOT NULL UNIQUE,
                candidate_fields TEXT NOT NULL,
                field_evidence TEXT NOT NULL,
                validation_issues TEXT NOT NULL,
                duplicate_candidates TEXT NOT NULL,
                saved_transaction_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(capture_id) REFERENCES capture_jobs(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_drafts_saved_tx ON drafts(saved_transaction_id)")

        // 3. 资金账户表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS accounts (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                card_last4 TEXT,
                archived_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """.trimIndent()
        )

        // 4. 交易分类表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                parent_id TEXT,
                applicable_type TEXT NOT NULL,
                icon_key TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                archived_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE SET NULL
            )
            """.trimIndent()
        )

        // 5. 项目表 (Project)
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                archived_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """.trimIndent()
        )

        // 6. 标签表 (Tag)
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS tags (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                archived_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """.trimIndent()
        )

        // 7. 正式账目流水主表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transactions (
                id TEXT PRIMARY KEY NOT NULL,
                origin_draft_id TEXT UNIQUE,
                type TEXT NOT NULL,
                amount_minor INTEGER NOT NULL,
                currency TEXT NOT NULL DEFAULT 'CNY',
                merchant_raw TEXT NOT NULL,
                merchant_normalized TEXT,
                occurred_on TEXT NOT NULL,
                occurred_at TEXT,
                event_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
                event_time_source TEXT NOT NULL,
                event_time_precision TEXT NOT NULL,
                payment_channel TEXT NOT NULL,
                account_id TEXT,
                transfer_to_account_id TEXT,
                category_id TEXT,
                project_id TEXT,
                note TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                CHECK (amount_minor > 0),
                FOREIGN KEY(origin_draft_id) REFERENCES drafts(id) ON DELETE SET NULL,
                FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE SET NULL,
                FOREIGN KEY(transfer_to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_occurred_on ON transactions(occurred_on)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_deleted_at ON transactions(deleted_at)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_project ON transactions(project_id)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id)")

        // 8. 账目扩展元数据表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transaction_metadata (
                transaction_id TEXT PRIMARY KEY NOT NULL,
                original_amount_minor INTEGER,
                discount_minor INTEGER,
                fee_minor INTEGER,
                payment_status TEXT NOT NULL DEFAULT 'SUCCESS',
                platform_transaction_no TEXT,
                merchant_order_no TEXT,
                identifier_completeness TEXT NOT NULL DEFAULT 'NONE',
                payment_method_label TEXT,
                FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )

        // 9. 交易-标签多对多关联表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transaction_tags (
                transaction_id TEXT NOT NULL,
                tag_id TEXT NOT NULL,
                PRIMARY KEY (transaction_id, tag_id),
                FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
                FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id)")

        // 10. 退款关联关系表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS refund_links (
                refund_transaction_id TEXT PRIMARY KEY NOT NULL,
                original_expense_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(refund_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
                FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_refund_original ON refund_links(original_expense_id)")

        // 11. 商户分类规则表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS classification_rules (
                id TEXT PRIMARY KEY NOT NULL,
                priority INTEGER NOT NULL DEFAULT 100,
                merchant_pattern TEXT NOT NULL,
                payment_channel TEXT,
                category_id TEXT NOT NULL,
                project_id TEXT,
                enabled INTEGER NOT NULL DEFAULT 1,
                version INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
            )
            """.trimIndent()
        )

        // 12. 强唯一性交易标识索引表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS confirmed_identifiers (
                namespace TEXT NOT NULL,
                identifier_type TEXT NOT NULL,
                complete_value TEXT NOT NULL,
                stable_event_kind TEXT NOT NULL,
                transaction_id TEXT NOT NULL,
                PRIMARY KEY (namespace, identifier_type, complete_value, stable_event_kind),
                FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_confirmed_identifiers_tx ON confirmed_identifiers(transaction_id)")

        // 13. WebView 桥接键值存储表
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS app_kv_store (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        onCreate(db)
    }

    fun saveKeyValue(key: String, value: String): Boolean {
        if (key.isBlank()) return false
        synchronized(writeLock) {
            val db = writableDatabase
            db.beginTransaction()
            return try {
                upsertKeyValueInternal(db, key, value, System.currentTimeMillis())
                db.setTransactionSuccessful()
                true
            } catch (e: Exception) {
                Log.e(TAG, "saveKeyValue failed for key=$key: ${e.message}", e)
                false
            } finally {
                try {
                    db.endTransaction()
                } catch (_: Throwable) {}
            }
        }
    }

    fun loadKeyValue(key: String): String {
        if (key.isBlank()) return ""
        return try {
            val db = readableDatabase
            db.rawQuery("SELECT value FROM app_kv_store WHERE key = ? LIMIT 1", arrayOf(key)).use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) ?: "" else ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "loadKeyValue failed for key=$key: ${e.message}", e)
            ""
        }
    }

    fun loadTransactionsJson(): String {
        return loadKeyValue(KEY_USER_TRANSACTIONS)
    }

    /**
     * 在单个事务中原子保存 `app_kv_store('user_transactions', jsonStr)`，
     * 并同步投影有效流水至 `transactions`、`transaction_metadata`、`confirmed_identifiers`。
     * 投影异常仅记录日志，绝不影响主 KV 持久化成功。
     */
    fun saveTransactionsJson(jsonStr: String): Boolean {
        synchronized(writeLock) {
            val db = writableDatabase
            val nowMs = System.currentTimeMillis()
            db.beginTransaction()
            return try {
                upsertKeyValueInternal(db, KEY_USER_TRANSACTIONS, jsonStr, nowMs)

                try {
                    projectTransactionsToRelationalTables(db, jsonStr, nowMs)
                } catch (projErr: Exception) {
                    Log.w(TAG, "Transaction relational projection warning (KV preserved): ${projErr.message}", projErr)
                }

                db.setTransactionSuccessful()
                true
            } catch (e: Exception) {
                Log.e(TAG, "saveTransactionsJson failed: ${e.message}", e)
                false
            } finally {
                try {
                    db.endTransaction()
                } catch (_: Throwable) {}
            }
        }
    }

    private fun upsertKeyValueInternal(db: SQLiteDatabase, key: String, value: String, nowMs: Long) {
        val values = ContentValues().apply {
            put("key", key)
            put("value", value)
            put("updated_at", nowMs)
        }
        db.insertWithOnConflict("app_kv_store", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun projectTransactionsToRelationalTables(db: SQLiteDatabase, jsonStr: String, nowMs: Long) {
        if (jsonStr.isBlank()) return
        val arr = JSONArray(jsonStr)
        val nowIso = formatIsoUtc(nowMs)
        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(nowMs))

        ensureBaseCategories(db, nowIso)

        val projectedIds = LinkedHashSet<String>(arr.length())
        val ensuredCategories = HashMap<String, String>()
        val ensuredAccounts = HashMap<String, String>()

        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val amountMinor = resolveAmountMinor(obj)
            if (amountMinor <= 0L) continue

            val rawId = obj.optString("id", "").trim()
            val txId = if (rawId.isNotEmpty()) rawId else "tx_proj_${i}_$nowMs"
            projectedIds.add(txId)

            val catName = listOf("parentCat", "catName", "category", "cat")
                .map { obj.optString(it, "").trim() }
                .firstOrNull { it.isNotEmpty() && it != "undefined" && it != "null" }
                ?: "其他支出"

            val txType = resolveTransactionType(obj, catName)
            val categoryId = ensuredCategories.getOrPut(catName) {
                ensureCategoryRow(db, catName, txType, nowIso)
            }

            val rawChannel = obj.optString("channel", "").trim()
            val rawAccount = obj.optString("account", "").trim()
            val paymentObj = obj.optJSONObject("payment")
            val paymentLabel = resolvePaymentLabel(rawChannel, rawAccount, paymentObj)
            val paymentChannel = mapPaymentChannelCode(rawChannel, paymentLabel)
            val accountId = if (paymentLabel.isNotBlank()) {
                ensuredAccounts.getOrPut(paymentLabel) {
                    ensureAccountRow(db, paymentLabel, paymentChannel, nowIso)
                }
            } else {
                null
            }

            val merchantRaw = listOf("merchant", "name", "merchantHeader")
                .map { obj.optString(it, "").trim() }
                .firstOrNull { it.isNotEmpty() }
                ?: "日常消费"
            val merchantNorm = obj.optString("merchantNormalized", "").trim().ifEmpty { merchantRaw }

            val rawTime = listOf("txTime", "orderTime", "fullTime", "time")
                .map { obj.optString(it, "").trim() }
                .firstOrNull { it.isNotEmpty() }
                ?: ""
            val occurredOn = resolveOccurredOn(obj, rawTime, todayStr)
            val occurredAt = rawTime.ifEmpty { null }
            val note = obj.optString("note", "").trim().ifEmpty { null }
            val deletedAt = if (obj.optBoolean("softDeleted", false)) nowIso else null

            val txValues = ContentValues().apply {
                put("id", txId)
                putNull("origin_draft_id")
                put("type", txType)
                put("amount_minor", amountMinor)
                put("currency", obj.optString("currency", "CNY").ifBlank { "CNY" })
                put("merchant_raw", merchantRaw)
                put("merchant_normalized", merchantNorm)
                put("occurred_on", occurredOn)
                if (occurredAt != null) put("occurred_at", occurredAt) else putNull("occurred_at")
                put("event_timezone", "Asia/Shanghai")
                put("event_time_source", if (rawTime.isNotEmpty()) "ocr_extracted" else "user_selected")
                put("event_time_precision", if (rawTime.contains(":")) "second" else "day")
                put("payment_channel", paymentChannel)
                if (accountId != null) put("account_id", accountId) else putNull("account_id")
                putNull("transfer_to_account_id")
                put("category_id", categoryId)
                putNull("project_id")
                if (note != null) put("note", note) else putNull("note")
                put("created_at", nowIso)
                put("updated_at", nowIso)
                if (deletedAt != null) put("deleted_at", deletedAt) else putNull("deleted_at")
            }
            db.insertWithOnConflict("transactions", null, txValues, SQLiteDatabase.CONFLICT_REPLACE)

            val orderId = listOf("orderId", "order_id", "platform_transaction_no")
                .map { obj.optString(it, "").trim() }
                .firstOrNull { it.isNotEmpty() }
            val completeness = classifyIdentifierCompleteness(orderId)

            val metaValues = ContentValues().apply {
                put("transaction_id", txId)
                putNull("original_amount_minor")
                putNull("discount_minor")
                putNull("fee_minor")
                put("payment_status", if (txType == "refund") "REFUNDED" else "SUCCESS")
                if (orderId != null) put("platform_transaction_no", orderId) else putNull("platform_transaction_no")
                putNull("merchant_order_no")
                put("identifier_completeness", completeness)
                put("payment_method_label", paymentLabel)
            }
            db.insertWithOnConflict("transaction_metadata", null, metaValues, SQLiteDatabase.CONFLICT_REPLACE)

            if (completeness == "COMPLETE" && orderId != null) {
                val namespace = when (paymentChannel) {
                    "wechat" -> "wechat_pay"
                    "alipay" -> "alipay"
                    "unionpay" -> "unionpay"
                    else -> paymentChannel
                }
                val eventKind = if (txType == "refund") "refund" else "payment"
                val idValues = ContentValues().apply {
                    put("namespace", namespace)
                    put("identifier_type", "platform_transaction_no")
                    put("complete_value", orderId)
                    put("stable_event_kind", eventKind)
                    put("transaction_id", txId)
                }
                db.insertWithOnConflict("confirmed_identifiers", null, idValues, SQLiteDatabase.CONFLICT_REPLACE)
            }
        }

        // 清理已从前端删除的旧流水记录（外键 ON DELETE CASCADE 自动清理 metadata 与 confirmed_identifiers）
        val existingIds = mutableListOf<String>()
        db.rawQuery("SELECT id FROM transactions", null).use { cursor ->
            while (cursor.moveToNext()) {
                existingIds.add(cursor.getString(0))
            }
        }
        val toDelete = existingIds.filter { it !in projectedIds }
        if (toDelete.isNotEmpty()) {
            for (staleId in toDelete) {
                db.delete("transactions", "id = ?", arrayOf(staleId))
            }
        }
    }

    private fun ensureBaseCategories(db: SQLiteDatabase, nowIso: String) {
        DEFAULT_CORE_CATEGORIES.forEachIndexed { idx, (id, name, applicableType) ->
            val values = ContentValues().apply {
                put("id", id)
                put("name", name)
                putNull("parent_id")
                put("applicable_type", applicableType)
                put("icon_key", id)
                put("sort_order", idx)
                putNull("archived_at")
                put("created_at", nowIso)
                put("updated_at", nowIso)
            }
            db.insertWithOnConflict("categories", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        }
    }

    private fun ensureCategoryRow(db: SQLiteDatabase, name: String, txType: String, nowIso: String): String {
        val preset = DEFAULT_CORE_CATEGORIES.firstOrNull { it.second == name }
        if (preset != null) return preset.first

        db.rawQuery("SELECT id FROM categories WHERE name = ? LIMIT 1", arrayOf(name)).use { c ->
            if (c.moveToFirst()) return c.getString(0)
        }

        val generatedId = "cat_${abs(name.hashCode())}"
        val values = ContentValues().apply {
            put("id", generatedId)
            put("name", name)
            putNull("parent_id")
            put("applicable_type", if (txType == "income") "income" else "both")
            put("icon_key", "cat_custom")
            put("sort_order", 100)
            putNull("archived_at")
            put("created_at", nowIso)
            put("updated_at", nowIso)
        }
        db.insertWithOnConflict("categories", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return generatedId
    }

    private fun ensureAccountRow(db: SQLiteDatabase, label: String, channelCode: String, nowIso: String): String {
        val accountId = "acc_${abs(label.hashCode())}"
        val kind = when {
            label.contains("信用卡") || label.contains("花呗") -> "credit_card"
            label.contains("储蓄卡") || label.contains("银行") -> "debit_card"
            channelCode == "cash" || label.contains("现金") -> "cash"
            channelCode in setOf("wechat", "alipay", "unionpay") -> "e_wallet"
            else -> "other"
        }
        val last4Match = Regex("[(\\[（](\\d{4})[)\\]）]").find(label)
        val last4 = last4Match?.groupValues?.getOrNull(1)
        val values = ContentValues().apply {
            put("id", accountId)
            put("name", label)
            put("kind", kind)
            if (last4 != null) put("card_last4", last4) else putNull("card_last4")
            putNull("archived_at")
            put("created_at", nowIso)
            put("updated_at", nowIso)
        }
        db.insertWithOnConflict("accounts", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return accountId
    }

    private fun resolveAmountMinor(obj: JSONObject): Long {
        val cents = obj.optLong("amountInCents", -1L)
        if (cents > 0L) return cents
        val minor = obj.optLong("amount_minor", -1L)
        if (minor > 0L) return minor
        val amt = obj.optDouble("amount", 0.0)
        return if (amt.isFinite() && amt > 0.0) (amt * 100.0).roundToLong() else 0L
    }

    private fun resolveTransactionType(obj: JSONObject, catName: String): String {
        val explicit = obj.optString("type", "").trim().lowercase(Locale.ROOT)
        return when {
            obj.optBoolean("refund", false) || explicit == "refund" -> "refund"
            explicit == "income" || catName == "工资收入" -> "income"
            explicit == "transfer" -> "transfer"
            else -> "expense"
        }
    }

    private fun resolvePaymentLabel(rawChannel: String, rawAccount: String, paymentObj: JSONObject?): String {
        val objDisplay = paymentObj?.optString("display_name", "")?.trim().orEmpty()
        if (objDisplay.isNotEmpty()) return objDisplay
        val objChan = paymentObj?.optString("channel", "")?.trim().orEmpty()
        val objSub = paymentObj?.optString("sub_type", "")?.trim().orEmpty()
        val chan = rawChannel.ifEmpty { objChan }
        val acc = rawAccount.ifEmpty { objSub }
        if (acc.contains("·")) return acc
        return when {
            chan.isNotEmpty() && acc.isNotEmpty() -> "$chan · $acc"
            acc.isNotEmpty() -> acc
            chan.isNotEmpty() -> chan
            else -> "微信 · 钱包"
        }
    }

    private fun mapPaymentChannelCode(rawChannel: String, label: String): String {
        val merged = "$rawChannel $label"
        return when {
            merged.contains("支付宝") || merged.contains("alipay", ignoreCase = true) -> "alipay"
            merged.contains("云闪付") || merged.contains("银联") || merged.contains("unionpay", ignoreCase = true) -> "unionpay"
            merged.contains("现金") || merged.contains("cash", ignoreCase = true) -> "cash"
            merged.contains("微信") || merged.contains("wechat", ignoreCase = true) -> "wechat"
            else -> "other"
        }
    }

    private fun resolveOccurredOn(obj: JSONObject, rawTime: String, fallbackToday: String): String {
        val txDate = obj.optString("txDate", "").trim()
        if (Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(txDate)) return txDate
        val match = Regex("(\\d{4}-\\d{2}-\\d{2})").find(rawTime)
        if (match != null) return match.groupValues[1]
        return fallbackToday
    }

    private fun classifyIdentifierCompleteness(orderId: String?): String {
        if (orderId.isNullOrBlank()) return "NONE"
        if (orderId.contains("*") || orderId.contains("•")) return "MASKED"
        if (orderId.startsWith("VLM_", ignoreCase = true) ||
            orderId.startsWith("LOCAL_", ignoreCase = true) ||
            orderId.startsWith("MOCK_", ignoreCase = true)
        ) {
            return "UNRELIABLE"
        }
        return if (orderId.length >= 10) "COMPLETE" else "TRUNCATED"
    }

    private fun formatIsoUtc(epochMs: Long): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date(epochMs))
    }
}
