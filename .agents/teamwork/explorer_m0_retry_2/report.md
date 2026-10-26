# Investigation & Proposed Fix Strategy: Android Keystore Master DB Key State Guarding

- **Agent**: `explorer_m0_retry_2`
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2`
- **Target File**: `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt`
- **Issue Reference**: Reviewer 2 Finding 3 (Major: Partial Key Preference Corruption Vulnerability in Android Keystore Wrapping)
- **Status**: Investigation Complete & Fix Formulated

---

## 1. Executive Summary

In `NativeCaptureHostApiImpl.kt:187-238`, `getOrCreateMasterDbKey()` wraps and persists a 32-byte (256-bit) SQLCipher master database encryption key using Android Keystore AES-256-GCM envelope encryption. 

Reviewer 2 identified a critical security and data integrity flaw:
> In `NativeCaptureHostApiImpl.kt:215`, if `existingEncrypted != null && existingIv != null` is false (e.g. if SharedPreferences write was interrupted, or one preference was removed or cleared), the implementation silently falls through to generate a brand new random master key, overwriting the existing encrypted database key in `SharedPreferences`. Any SQLite database encrypted with the prior key becomes irrevocably lost and inaccessible.

This investigation provides a comprehensive threat model analysis, state truth table, and a production-grade, hardened fix strategy that guarantees:
1. **Zero Silent Regeneration**: Any asymmetric, missing, or blank state between ciphertext and IV triggers an immediate, explicit `IllegalStateException("CORRUPTED_KEYSTORE_PREFS: ...")`.
2. **Key Immutability on Partial Read**: Existing key material is never overwritten when SharedPreferences state is incomplete or corrupted.
3. **Hardware Key Loss Detection**: If SharedPreferences holds an encrypted key but `AndroidKeyStore` is missing the wrapping alias `KEY_ALIAS` (e.g. after lockscreen PIN reset or device restore), the system fails fast with `KEYSTORE_KEY_LOST` instead of generating a useless mismatched hardware key.
4. **Synchronous Atomic Persistence**: Switching from asynchronous `.apply()` to synchronous atomic `.commit()` ensures that keys are guaranteed to be flushed to persistent storage before returning the raw key to SQLite.
5. **Orphaned Database Guard**: If a non-empty `singwallet.db` database file exists on disk but SharedPreferences has no encryption key, key generation is refused (`ORPHAN_DATABASE_FOUND`) to prevent initializing a new key against an incompatible existing database.

---

## 2. Root Cause & Threat Model Analysis

### 2.1 Code Vulnerability Breakdown (Before Fix)

```kotlin
// Existing code in NativeCaptureHostApiImpl.kt:
val existingEncrypted = prefs.getString(PREF_ENCRYPTED_DB_KEY, null)
val existingIv = prefs.getString(PREF_DB_KEY_IV, null)

// Vulnerability 1: Always generates wrapping key before checking prefs
if (!keyStore.containsAlias(KEY_ALIAS)) {
    // Generates NEW Keystore alias even if ciphertext exists!
    ...
}

val secretKey = keyStore.getKey(KEY_ALIAS, null) as SecretKey

// Vulnerability 2: If either is null, evaluates to false and FALLS THROUGH
if (existingEncrypted != null && existingIv != null) {
    ...
    return cipher.doFinal(encryptedBytes)
}

// Catastrophic Fallthrough: Generates a brand new raw key and OVERWRITES prefs!
val rawKey = ByteArray(32)
SecureRandom().nextBytes(rawKey)
...
prefs.edit()
    .putString(PREF_ENCRYPTED_DB_KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP))
    .putString(PREF_DB_KEY_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
    .apply() // Vulnerability 3: Asynchronous write, unverified success
return rawKey
```

### 2.2 Six Core Failure Modes

| # | Failure Mode | Trigger / Condition | Consequence in Existing Code | Proposed Remediation |
|---|--------------|---------------------|------------------------------|----------------------|
| **F1** | **Ciphertext Present, IV Missing** | Process terminated during write; partial backup restore; corrupted XML | Falls through, generates new key, overwrites `PREF_ENCRYPTED_DB_KEY`. Previous database permanently destroyed. | Guard: `hasEncrypted != hasIv` throws `CORRUPTED_KEYSTORE_PREFS`. Halts execution, preserves ciphertext. |
| **F2** | **IV Present, Ciphertext Missing** | Manual deletion; preference tampering; corrupted XML | Falls through, generates new key, overwrites `PREF_DB_KEY_IV`. | Guard: `hasEncrypted != hasIv` throws `CORRUPTED_KEYSTORE_PREFS`. |
| **F3** | **Empty or Blank String Values** | XML entry exists with `""` value | `getString() != null` is true! Fails during decryption with uninformative exception. | Guard: `!existingEncrypted.isNullOrBlank()` required for both entries. |
| **F4** | **Hardware Wrapping Key Missing** | App data restored to new device without hardware TEE keys; system PIN reset | Generates new Keystore alias, then decryption fails with `AEADBadTagException`, masking the underlying hardware key loss. | Guard: Check `!keyStore.containsAlias(KEY_ALIAS)` when prefs exist. Throw `KEYSTORE_KEY_LOST`. Do not generate new key. |
| **F5** | **Asynchronous `.apply()` Data Loss** | Process killed or device power lost immediately after launch; storage full | `.apply()` writes in background. Caller receives `rawKey`, encrypts database. Key was never written to disk. On reboot, database cannot be opened. | Replace `.apply()` with `.commit()`. Verify return value; throw `PREFS_COMMIT_FAILED` if `false`. |
| **F6** | **Orphaned Database on Disk** | App data partially cleared; DB restored from file backup without SharedPreferences | Generates new random key. App opens existing DB with mismatched key, causing SQLCipher `file is not a database` crash or data corruption. | Check `context.getDatabasePath("singwallet.db")`. If exists and > 0 bytes without prefs, throw `ORPHAN_DATABASE_FOUND`. |

---

## 3. Strict State Transition & Truth Table

Let:
- $E$: `prefs.contains(PREF_ENCRYPTED_DB_KEY) && !prefs.getString(PREF_ENCRYPTED_DB_KEY, null).isNullOrBlank()`
- $IV$: `prefs.contains(PREF_DB_KEY_IV) && !prefs.getString(PREF_DB_KEY_IV, null).isNullOrBlank()`
- $KS$: `keyStore.containsAlias(KEY_ALIAS)`
- $DB$: `context.getDatabasePath("singwallet.db").let { it.exists() && it.length() > 0 }`

| State | $E$ | $IV$ | $KS$ | $DB$ | Classification | Action Taken | Rationale |
|---|:---:|:---:|:---:|:---:|---|---|---|
| **S1** | `F` | `F` | `F` | `F` | Clean First Run | Generate $KS$, generate $rawKey$, encrypt, atomic `commit()`, return $rawKey$ | Normal initial setup for new installation |
| **S2** | `F` | `F` | `T` | `F` | Clean First Run (Keystore retained) | Use existing $KS$, generate $rawKey$, encrypt, atomic `commit()`, return $rawKey$ | Safe reuse of hardware alias when no prior prefs exist |
| **S3** | `T` | `T` | `T` | `T/F` | Normal Subsequent Run | Decrypt $E$ using $IV$ with $KS$, validate 32-byte length, return $rawKey$ | Normal decryption path; does not touch SharedPreferences |
| **S4** | `T` | `F` | `*` | `*` | **Asymmetric Corruption** | **Throw `CORRUPTED_KEYSTORE_PREFS`** | Ciphertext exists without IV; never overwrite |
| **S5** | `F` | `T` | `*` | `*` | **Asymmetric Corruption** | **Throw `CORRUPTED_KEYSTORE_PREFS`** | IV exists without ciphertext; never overwrite |
| **S6** | `T` | `T` | `F` | `*` | **Hardware Key Lost** | **Throw `KEYSTORE_KEY_LOST`** | Wrapping key missing from TEE; new key cannot decrypt existing data |
| **S7** | `F` | `F` | `*` | `T` | **Orphaned Database** | **Throw `ORPHAN_DATABASE_FOUND`** | Database file exists but key is missing; refuse to generate mismatching key |

---

## 4. Proposed Concrete Code Implementation

### 4.1 Companion Constants Additions

```kotlin
companion object {
    private const val ANDROID_KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "SingWalletMasterDbKey_v1"
    private const val PENDING_DIR_NAME = "pending_captures"
    private const val PREFS_NAME = "singwallet_sec_prefs"
    private const val PREF_ENCRYPTED_DB_KEY = "encrypted_db_key"
    private const val PREF_DB_KEY_IV = "db_key_iv"
    private const val DATABASE_NAME = "singwallet.db"
    private const val MASTER_KEY_SIZE_BYTES = 32
    private const val GCM_TAG_LENGTH_BITS = 128
    private val SAFE_CAPTURE_ID_REGEX = Regex("^[a-zA-Z0-9_-]+$")
}
```

### 4.2 Hardened `getOrCreateMasterDbKey()` Method

```kotlin
    @Synchronized
    private fun getOrCreateMasterDbKey(): ByteArray {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hasEncrypted = prefs.contains(PREF_ENCRYPTED_DB_KEY)
        val hasIv = prefs.contains(PREF_DB_KEY_IV)
        val existingEncrypted = prefs.getString(PREF_ENCRYPTED_DB_KEY, null)
        val existingIv = prefs.getString(PREF_DB_KEY_IV, null)

        val isEncryptedPresent = hasEncrypted && !existingEncrypted.isNullOrBlank()
        val isIvPresent = hasIv && !existingIv.isNullOrBlank()

        // 1. Strict State Guard: Detect partial or corrupted SharedPreferences state
        if (hasEncrypted != hasIv || isEncryptedPresent != isIvPresent) {
            throw IllegalStateException(
                "CORRUPTED_KEYSTORE_PREFS: Incomplete master key state detected in SharedPreferences " +
                "(hasEncrypted=$hasEncrypted, hasIv=$hasIv, isEncryptedPresent=$isEncryptedPresent, isIvPresent=$isIvPresent). " +
                "Refusing to regenerate key to prevent permanent database loss."
            )
        }

        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE_PROVIDER).apply { load(null) }

        // 2. Existing Key Path: Decrypt existing master key
        if (isEncryptedPresent && isIvPresent) {
            if (!keyStore.containsAlias(KEY_ALIAS)) {
                throw IllegalStateException(
                    "KEYSTORE_KEY_LOST: Encrypted database key found in SharedPreferences, " +
                    "but hardware wrapping key '$KEY_ALIAS' is missing from AndroidKeyStore. " +
                    "Refusing to regenerate key to avoid state corruption."
                )
            }

            val secretKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
                ?: throw IllegalStateException("KEYSTORE_INVALID_KEY: Key '$KEY_ALIAS' is not a SecretKey")

            val iv: ByteArray = try {
                android.util.Base64.decode(existingIv, android.util.Base64.NO_WRAP)
            } catch (e: Exception) {
                throw IllegalStateException("CORRUPTED_IV_BASE64: Failed to decode Base64 IV: ${e.message}", e)
            }

            val encryptedBytes: ByteArray = try {
                android.util.Base64.decode(existingEncrypted, android.util.Base64.NO_WRAP)
            } catch (e: Exception) {
                throw IllegalStateException("CORRUPTED_CIPHERTEXT_BASE64: Failed to decode Base64 ciphertext: ${e.message}", e)
            }

            if (iv.isEmpty()) {
                throw IllegalStateException("CORRUPTED_IV: Decoded IV is empty")
            }
            if (encryptedBytes.size < 16) {
                throw IllegalStateException("CORRUPTED_CIPHERTEXT: Encrypted bytes too short (${encryptedBytes.size} bytes)")
            }

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            val rawKey = try {
                cipher.doFinal(encryptedBytes)
            } catch (e: Exception) {
                throw IllegalStateException("KEY_DECRYPTION_FAILED: Failed to decrypt master key: ${e.message}", e)
            }

            if (rawKey.size != MASTER_KEY_SIZE_BYTES) {
                throw IllegalStateException(
                    "INVALID_KEY_LENGTH: Decrypted master key is ${rawKey.size} bytes, expected $MASTER_KEY_SIZE_BYTES"
                )
            }
            return rawKey
        }

        // 3. Clean Initial Generation Path:
        // Neither key exists in SharedPreferences.
        // Defense-in-depth: Check for orphaned database file before generating a new key.
        val dbFile = context.getDatabasePath(DATABASE_NAME)
        if (dbFile.exists() && dbFile.length() > 0) {
            throw IllegalStateException(
                "ORPHAN_DATABASE_FOUND: Database file '${dbFile.name}' exists (${dbFile.length()} bytes), " +
                "but no encryption key was found in SharedPreferences. " +
                "Refusing to generate a new key to avoid data corruption."
            )
        }

        // Ensure Keystore wrapping key exists
        if (!keyStore.containsAlias(KEY_ALIAS)) {
            val keyGenerator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE_PROVIDER
            )
            keyGenerator.init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            keyGenerator.generateKey()
        }

        val secretKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("KEYSTORE_GENERATE_FAILED: Generated key '$KEY_ALIAS' is null or not a SecretKey")

        // Generate 32 cryptographically secure random bytes
        val rawKey = ByteArray(MASTER_KEY_SIZE_BYTES)
        SecureRandom().nextBytes(rawKey)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv ?: throw IllegalStateException("CIPHER_IV_NULL: Cipher generated null IV for AES-GCM")
        val encrypted = cipher.doFinal(rawKey)

        // Atomically commit to persistent storage (commit() is synchronous, unlike apply())
        val committed = prefs.edit()
            .putString(PREF_ENCRYPTED_DB_KEY, android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP))
            .putString(PREF_DB_KEY_IV, android.util.Base64.encodeToString(iv, android.util.Base64.NO_WRAP))
            .commit()

        if (!committed) {
            throw IllegalStateException("PREFS_COMMIT_FAILED: Failed to atomically commit database encryption key to SharedPreferences")
        }

        return rawKey
    }
```

---

## 5. Machine-Applicable Patch Reference

A unified git patch file has been authored and verified at:
`c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch`

Worker agents can apply this patch directly using git or standard patch tools:
```powershell
git apply c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch
```

---

## 6. Pigeon & Flutter Exception Propagation

When `getOrCreateMasterDbKey()` throws an `IllegalStateException`, the execution flow operates as follows:
1. `NativeCaptureHostApiImpl.getOrCreateDatabaseKey` catches `Exception` and returns `callback(Result.failure(e))`.
2. In `NativeBridge.g.kt`, Pigeon wraps the exception:
   ```kotlin
   val error = result.exceptionOrNull()
   if (error != null) {
       reply.reply(wrapError(error))
   }
   ```
   Because `error` is an `IllegalStateException`, Pigeon packages:
   - `code`: `"IllegalStateException"`
   - `message`: `"CORRUPTED_KEYSTORE_PREFS: Incomplete master key state detected..."`
   - `details`: `"Cause: ... Stacktrace: ..."`
3. In `lib/core/native/native_bridge_service.dart:109-119`:
   ```dart
   try {
     return await _hostApi.getOrCreateDatabaseKey();
   } on PlatformException catch (e) {
     throw NativeBridgeException(
       code: e.code,
       message: e.message ?? 'Failed to access hardware database key',
       details: e.details,
     );
   }
   ```
4. In `pigeon_stress_challenge_test.dart` (lines 457-471), this behavior is already tested and verified: `PlatformException` is converted into `NativeBridgeException` and propagates to the database initialization lifecycle.
5. In M1-A database initialization: if `getOrCreateDatabaseKey()` fails, the database opening is aborted. **No SQLite connection is opened, no data is overwritten, and the existing database file remains intact.**

---

## 7. Verification Method

### 7.1 Static Analysis and Syntax Verification
Verify that the project compiles and passes static analysis:
```powershell
C:\Other\Dev\flutter\bin\flutter.bat analyze
C:\Other\Dev\flutter\bin\flutter.bat test
python test_docs_integrity.py
```
All commands must exit with code 0.

### 7.2 Defensive Edge-Case Verification Plan
1. **Test Partial Prefs State**:
   - Write only `encrypted_db_key` to `singwallet_sec_prefs`.
   - Call `getOrCreateMasterDbKey()`.
   - Assert `IllegalStateException` with code `CORRUPTED_KEYSTORE_PREFS` is thrown.
   - Verify `encrypted_db_key` value in SharedPreferences remains unaltered.
2. **Test Missing Keystore Wrapping Key**:
   - Write valid `encrypted_db_key` and `db_key_iv` to SharedPreferences.
   - Delete alias `SingWalletMasterDbKey_v1` from AndroidKeyStore.
   - Call `getOrCreateMasterDbKey()`.
   - Assert `IllegalStateException` with code `KEYSTORE_KEY_LOST` is thrown.
   - Verify no new key alias was created in KeyStore and prefs were not overwritten.
3. **Test Commit Verification**:
   - Verify `prefs.edit()...commit()` returns `true` and is synchronous.
4. **Test Orphaned Database Guard**:
   - Create dummy `singwallet.db` (e.g. 1024 bytes) in `context.getDatabasePath()`.
   - Ensure SharedPreferences is empty.
   - Call `getOrCreateMasterDbKey()`.
   - Assert `IllegalStateException` with code `ORPHAN_DATABASE_FOUND` is thrown.
