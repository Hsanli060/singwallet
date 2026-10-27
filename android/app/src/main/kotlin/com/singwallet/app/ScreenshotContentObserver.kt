package com.singwallet.app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore

/**
 * Monitors [MediaStore.Images.Media.EXTERNAL_CONTENT_URI] for newly created system screenshots
 * (e.g. triggered via Xiaomi HyperOS / Android "Back Tap -> Screenshot" while viewing bills
 * in WeChat or Alipay).
 *
 * Safeguards:
 * 1. Android 10+ (`IS_PENDING == 1`) write-in-progress detection: skips incomplete files until
 *    `IS_PENDING == 0` is committed by the system screenshot service.
 * 2. Strict path & filename keyword filtering (`screenshot`, `screenshots`, `截屏`, `屏幕截图`).
 * 3. Strict recency window (`DATE_ADDED` within [MAX_SCREENSHOT_AGE_SECONDS] = 15s) so historical
 *    gallery photos are never scanned or ingested.
 * 4. Multi-key deduplication & time-window debounce across `_ID`, item `Uri`, and relative path
 *    to prevent duplicate callbacks when MediaStore emits multiple `onChange` events per capture.
 */
class ScreenshotContentObserver(
    private val context: Context,
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val onScreenshotCaptured: (Uri) -> Unit
) : ContentObserver(mainHandler) {

    companion object {
        private const val MAX_SCREENSHOT_AGE_SECONDS = 15L
        private const val CLOCK_SKEW_TOLERANCE_SECONDS = 5L
        private const val DEBOUNCE_WINDOW_MS = 2500L
        private const val MAX_REMEMBERED_ENTRIES = 128
        private const val PENDING_RETRY_DELAY_MS = 500L
        private const val MAX_PENDING_RETRIES = 4

        private val SCREENSHOT_KEYWORDS = listOf(
            "screenshot",
            "screenshots",
            "截屏",
            "屏幕截图",
            "screen_shot"
        )

        internal fun matchesScreenshotPathOrName(
            displayName: String?,
            relativePath: String?,
            dataPath: String?
        ): Boolean {
            val candidates = listOfNotNull(displayName, relativePath, dataPath)
            if (candidates.isEmpty()) return false
            return candidates.any { candidate ->
                SCREENSHOT_KEYWORDS.any { keyword ->
                    candidate.contains(keyword, ignoreCase = true)
                }
            }
        }

        internal fun isRecentTimestamp(dateAddedRaw: Long, nowEpochMillis: Long): Boolean {
            if (dateAddedRaw <= 0L) return false
            // MediaStore DATE_ADDED is standardly in epoch seconds; normalize if OEM reports ms.
            val dateAddedSeconds = if (dateAddedRaw > 100_000_000_000L) {
                dateAddedRaw / 1000L
            } else {
                dateAddedRaw
            }
            val nowSeconds = nowEpochMillis / 1000L
            val ageSeconds = nowSeconds - dateAddedSeconds
            return ageSeconds in -CLOCK_SKEW_TOLERANCE_SECONDS..MAX_SCREENSHOT_AGE_SECONDS
        }
    }

    private val lock = Any()
    private val completedMediaIds = LinkedHashSet<Long>()
    private val completedItemUris = LinkedHashSet<String>()
    private val completedFileKeys = LinkedHashSet<String>()
    private var lastCapturedFileKey: String? = null
    private var lastCaptureTimeMs: Long = 0L

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        inspectMediaChange(uri, retryAttempt = 0)
    }

    private fun inspectMediaChange(uri: Uri?, retryAttempt: Int) {
        val specificRowId = uri?.lastPathSegment?.toLongOrNull()

        synchronized(lock) {
            if (specificRowId != null && completedMediaIds.contains(specificRowId)) {
                return
            }
            if (specificRowId != null && uri != null && completedItemUris.contains(uri.toString())) {
                return
            }
        }

        val nowMs = System.currentTimeMillis()
        val projection = buildProjection()

        val cursor: Cursor? = try {
            queryCandidateScreenshot(uri, specificRowId, projection, nowMs)
        } catch (_: SecurityException) {
            // Runtime media permission not yet granted; fail silently without crashing.
            null
        } catch (_: Exception) {
            null
        }

        cursor?.use { c ->
            if (!c.moveToFirst()) return

            val mediaId = c.getLongOrNull(MediaStore.Images.Media._ID) ?: specificRowId ?: return
            val displayName = c.getStringOrNull(MediaStore.Images.Media.DISPLAY_NAME)
            val dateAdded = c.getLongOrNull(MediaStore.Images.Media.DATE_ADDED) ?: 0L
            @Suppress("DEPRECATION")
            val dataPath = c.getStringOrNull(MediaStore.Images.Media.DATA)

            val relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                c.getStringOrNull(MediaStore.Images.Media.RELATIVE_PATH)
            } else {
                null
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val isPending = c.getIntOrNull(MediaStore.Images.Media.IS_PENDING) ?: 0
                if (isPending == 1) {
                    // File is still being written by system screenshot service.
                    // Do NOT mark as completed yet; wait for IS_PENDING == 0 notification
                    // and schedule a bounded fallback check in case OEM suppresses update notify.
                    if (retryAttempt < MAX_PENDING_RETRIES) {
                        val retryUri = if (specificRowId != null && uri != null) {
                            uri
                        } else {
                            ContentUris.withAppendedId(
                                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                                mediaId
                            )
                        }
                        mainHandler.postDelayed(
                            { inspectMediaChange(retryUri, retryAttempt + 1) },
                            PENDING_RETRY_DELAY_MS
                        )
                    }
                    return
                }
            }

            // 1. Strict path / filename filter
            if (!matchesScreenshotPathOrName(displayName, relativePath, dataPath)) {
                return
            }

            // 2. Strict 15-second recency filter (never ingest historical photos)
            if (!isRecentTimestamp(dateAdded, nowMs)) {
                return
            }

            val targetUri = if (specificRowId == mediaId && uri != null) {
                uri
            } else {
                ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, mediaId)
            }

            val fileKey = buildFileKey(displayName, relativePath, dataPath, mediaId)

            // 3. Atomic deduplication & debounce check before dispatching
            val shouldDispatch = synchronized(lock) {
                if (completedMediaIds.contains(mediaId) ||
                    completedItemUris.contains(targetUri.toString()) ||
                    completedFileKeys.contains(fileKey)
                ) {
                    false
                } else if (
                    fileKey == lastCapturedFileKey &&
                    (nowMs - lastCaptureTimeMs) < DEBOUNCE_WINDOW_MS
                ) {
                    false
                } else {
                    rememberBounded(completedMediaIds, mediaId)
                    rememberBounded(completedItemUris, targetUri.toString())
                    if (specificRowId != null && uri != null) {
                        rememberBounded(completedItemUris, uri.toString())
                    }
                    rememberBounded(completedFileKeys, fileKey)
                    lastCapturedFileKey = fileKey
                    lastCaptureTimeMs = nowMs
                    true
                }
            }

            if (shouldDispatch) {
                onScreenshotCaptured(targetUri)
            }
        }
    }

    private fun queryCandidateScreenshot(
        uri: Uri?,
        specificRowId: Long?,
        projection: Array<String>,
        nowMs: Long
    ): Cursor? {
        val resolver = context.contentResolver
        if (specificRowId != null && uri != null) {
            return resolver.query(uri, projection, null, null, null)
        }

        val minDateAddedSec = (nowMs / 1000L) - MAX_SCREENSHOT_AGE_SECONDS
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val queryArgs = Bundle().apply {
                putString(
                    ContentResolver.QUERY_ARG_SQL_SELECTION,
                    "${MediaStore.Images.Media.DATE_ADDED} >= ?"
                )
                putStringArray(
                    ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                    arrayOf(minDateAddedSec.toString())
                )
                putString(
                    ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                    "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC"
                )
                putInt(ContentResolver.QUERY_ARG_LIMIT, 1)
            }
            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                queryArgs,
                null
            )
        } else {
            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                "${MediaStore.Images.Media.DATE_ADDED} >= ?",
                arrayOf(minDateAddedSec.toString()),
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )
        }
    }

    private fun buildProjection(): Array<String> {
        @Suppress("DEPRECATION")
        val baseColumns = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATA
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            baseColumns.add(MediaStore.Images.Media.RELATIVE_PATH)
            baseColumns.add(MediaStore.Images.Media.IS_PENDING)
        }
        return baseColumns.toTypedArray()
    }

    private fun buildFileKey(
        displayName: String?,
        relativePath: String?,
        dataPath: String?,
        mediaId: Long
    ): String {
        val pathPart = relativePath?.trim()?.lowercase()
            ?: dataPath?.trim()?.lowercase()
            ?: ""
        val namePart = displayName?.trim()?.lowercase() ?: mediaId.toString()
        return "$pathPart|$namePart"
    }

    private fun <T> rememberBounded(set: LinkedHashSet<T>, value: T) {
        if (set.size >= MAX_REMEMBERED_ENTRIES) {
            val iterator = set.iterator()
            if (iterator.hasNext()) {
                iterator.next()
                iterator.remove()
            }
        }
        set.add(value)
    }

    /**
     * Cancels any pending delayed retry checks when observer is unregistered.
     */
    fun dispose() {
        mainHandler.removeCallbacksAndMessages(null)
    }

    private fun Cursor.getStringOrNull(columnName: String): String? {
        val idx = getColumnIndex(columnName)
        return if (idx >= 0 && !isNull(idx)) getString(idx) else null
    }

    private fun Cursor.getLongOrNull(columnName: String): Long? {
        val idx = getColumnIndex(columnName)
        return if (idx >= 0 && !isNull(idx)) getLong(idx) else null
    }

    private fun Cursor.getIntOrNull(columnName: String): Int? {
        val idx = getColumnIndex(columnName)
        return if (idx >= 0 && !isNull(idx)) getInt(idx) else null
    }
}
