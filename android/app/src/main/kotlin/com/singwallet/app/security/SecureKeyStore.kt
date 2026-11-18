package com.singwallet.app.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 硬件级密钥存储 (Android Keystore AES-256-GCM).
 *
 * 将敏感凭据（VLM API Key、GitHub OTA Token）加密存储于 `singwallet_secure_prefs`，
 * 密文格式：`v1:<iv_b64>:<ct_b64>`。
 * 读取时若检测到旧版明文存储 (`singwallet_ai_prefs` / `singwallet_ota_prefs`)，
 * 自动完成无缝加密迁移并立即擦除旧明文键值。
 */
object SecureKeyStore {

    private const val TAG = "SecureKeyStore"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "singwallet_master_aes_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val CIPHER_VERSION = "v1"

    private const val PREFS_SECURE = "singwallet_secure_prefs"
    private const val PREFS_AI_LEGACY = "singwallet_ai_prefs"
    private const val PREFS_OTA_LEGACY = "singwallet_ota_prefs"

    private const val KEY_VLM_API_KEY = "vlm_api_key"
    private const val KEY_GITHUB_TOKEN = "github_token"

    private val lock = Any()

    fun getVlmApiKey(context: Context): String {
        return getSecretWithMigration(
            context = context,
            secureKey = KEY_VLM_API_KEY,
            legacyPrefsName = PREFS_AI_LEGACY,
            legacyKey = KEY_VLM_API_KEY
        )
    }

    fun setVlmApiKey(context: Context, apiKey: String) {
        setSecretAndEraseLegacy(
            context = context,
            secureKey = KEY_VLM_API_KEY,
            value = apiKey,
            legacyPrefsName = PREFS_AI_LEGACY,
            legacyKey = KEY_VLM_API_KEY
        )
    }

    fun getGithubToken(context: Context): String {
        return getSecretWithMigration(
            context = context,
            secureKey = KEY_GITHUB_TOKEN,
            legacyPrefsName = PREFS_OTA_LEGACY,
            legacyKey = KEY_GITHUB_TOKEN
        )
    }

    fun setGithubToken(context: Context, token: String) {
        setSecretAndEraseLegacy(
            context = context,
            secureKey = KEY_GITHUB_TOKEN,
            value = token,
            legacyPrefsName = PREFS_OTA_LEGACY,
            legacyKey = KEY_GITHUB_TOKEN
        )
    }

    private fun getSecretWithMigration(
        context: Context,
        secureKey: String,
        legacyPrefsName: String,
        legacyKey: String
    ): String {
        val appCtx = context.applicationContext
        synchronized(lock) {
            val securePrefs = appCtx.getSharedPreferences(PREFS_SECURE, Context.MODE_PRIVATE)
            val legacyPrefs = appCtx.getSharedPreferences(legacyPrefsName, Context.MODE_PRIVATE)

            val encryptedVal = securePrefs.getString(secureKey, null)
            val legacyVal = legacyPrefs.getString(legacyKey, null)

            if (!encryptedVal.isNullOrBlank()) {
                // 若旧 prefs 仍残留明文，确保立即擦除
                if (legacyPrefs.contains(legacyKey)) {
                    legacyPrefs.edit().remove(legacyKey).apply()
                }
                val decrypted = decryptFromStorage(encryptedVal)
                if (decrypted.isNotEmpty() || legacyVal.isNullOrBlank()) {
                    return decrypted
                }
            }

            if (!legacyVal.isNullOrBlank()) {
                val trimmed = legacyVal.trim()
                if (trimmed.isNotEmpty()) {
                    val cipherText = encryptForStorage(trimmed)
                    if (cipherText != null) {
                        securePrefs.edit().putString(secureKey, cipherText).apply()
                        legacyPrefs.edit().remove(legacyKey).apply()
                        Log.i(TAG, "Migrated secret [$secureKey] from legacy prefs to Keystore")
                    }
                    return trimmed
                }
            }

            if (legacyPrefs.contains(legacyKey)) {
                legacyPrefs.edit().remove(legacyKey).apply()
            }
            return ""
        }
    }

    private fun setSecretAndEraseLegacy(
        context: Context,
        secureKey: String,
        value: String,
        legacyPrefsName: String,
        legacyKey: String
    ) {
        val appCtx = context.applicationContext
        val trimmed = value.trim()
        synchronized(lock) {
            val securePrefs = appCtx.getSharedPreferences(PREFS_SECURE, Context.MODE_PRIVATE)
            val legacyPrefs = appCtx.getSharedPreferences(legacyPrefsName, Context.MODE_PRIVATE)

            if (trimmed.isEmpty()) {
                securePrefs.edit().remove(secureKey).apply()
            } else {
                val cipherText = encryptForStorage(trimmed)
                    ?: throw IllegalStateException("Failed to encrypt secret with Android Keystore")
                securePrefs.edit().putString(secureKey, cipherText).apply()
            }

            if (legacyPrefs.contains(legacyKey)) {
                legacyPrefs.edit().remove(legacyKey).apply()
            }
        }
    }

    private fun getOrCreateMasterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = try {
            keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to retrieve existing keystore key, regenerating: ${e.message}")
            null
        }
        if (existing != null) {
            return existing
        }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encryptForStorage(plainText: String): String? {
        return try {
            val key = getOrCreateMasterKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val cipherBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
            val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
            val ctB64 = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
            "$CIPHER_VERSION:$ivB64:$ctB64"
        } catch (e: Throwable) {
            Log.e(TAG, "Keystore encryption failed: ${e.message}", e)
            null
        }
    }

    private fun decryptFromStorage(stored: String): String {
        val parts = stored.split(":")
        if (parts.size != 3 || parts[0] != CIPHER_VERSION) {
            Log.w(TAG, "Unexpected ciphertext format in secure prefs")
            return ""
        }
        return try {
            val iv = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipherBytes = Base64.decode(parts[2], Base64.NO_WRAP)
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val key = keyStore.getKey(KEY_ALIAS, null) as? SecretKey ?: return ""
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
            val plainBytes = cipher.doFinal(cipherBytes)
            String(plainBytes, Charsets.UTF_8)
        } catch (e: Throwable) {
            Log.w(TAG, "Keystore decryption failed: ${e.message}")
            ""
        }
    }
}
