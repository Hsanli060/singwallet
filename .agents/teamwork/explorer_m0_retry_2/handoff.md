# Handoff Report: Android Keystore State Guarding Fix Strategy

- **Agent**: `explorer_m0_retry_2` (Explorer & Synthesis)
- **Parent**: `orchestrator_1` (Conversation ID: `0be8f589-cb64-4c3b-aed0-2d1a129de39c`)
- **Working Directory**: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2`
- **Date**: 2026-10-22
- **Handoff Type**: Hard Handoff (Investigation & Proposal Complete)
- **Status**: Ready for Implementation (by Worker)

---

## 1. Observation

1. **Vulnerability in `NativeCaptureHostApiImpl.kt` (lines 190-238)**:
   - Line 190-191:
     ```kotlin
     val existingEncrypted = prefs.getString(PREF_ENCRYPTED_DB_KEY, null)
     val existingIv = prefs.getString(PREF_DB_KEY_IV, null)
     ```
   - Lines 195-211:
     ```kotlin
     if (!keyStore.containsAlias(KEY_ALIAS)) {
         val keyGenerator = KeyGenerator.getInstance(...)
         ...
         keyGenerator.generateKey()
     }
     ```
     This check occurs unconditionally before verifying SharedPreferences state, meaning if SharedPreferences contains an encrypted key but `KEY_ALIAS` is lost from AndroidKeyStore, a brand new wrapping key is generated that can never decrypt the existing ciphertext.
   - Lines 215-221:
     ```kotlin
     if (existingEncrypted != null && existingIv != null) {
         val cipher = Cipher.getInstance("AES/GCM/NoPadding")
         val iv = android.util.Base64.decode(existingIv, android.util.Base64.NO_WRAP)
         cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
         val encryptedBytes = android.util.Base64.decode(existingEncrypted, android.util.Base64.NO_WRAP)
         return cipher.doFinal(encryptedBytes)
     }
     ```
     If `existingEncrypted != null` but `existingIv == null` (or vice versa, or if either is empty/blank), the `if` condition evaluates to `false`.
   - Lines 224-237:
     ```kotlin
     // Generate 32 raw bytes for SQLCipher master key
     val rawKey = ByteArray(32)
     SecureRandom().nextBytes(rawKey)

     val cipher = Cipher.getInstance("AES/GCM/NoPadding")
     cipher.init(Cipher.ENCRYPT_MODE, secretKey)
     val iv = cipher.iv
     val encrypted = cipher.doFinal(rawKey)

     prefs.edit()
         .putString(PREF_ENCRYPTED_DB_KEY, android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP))
         .putString(PREF_DB_KEY_IV, android.util.Base64.encodeToString(iv, android.util.Base64.NO_WRAP))
         .apply()

     return rawKey
     ```
     Execution silently falls through to generate a new key and overwrite the existing preference with newly encrypted bytes. Any database previously encrypted with the original key is permanently destroyed.
   - Line 235 uses `.apply()`, which writes asynchronously to disk without checking if disk persistence succeeded.

2. **Upstream Reviewer 2 Assessment (`reviewer_m0_2/report.md:64-70`)**:
   - Quoting Finding 3: *"In NativeCaptureHostApiImpl.kt:215, if `existingEncrypted != null && existingIv != null` is false (e.g. if SharedPreferences was interrupted or one key was cleared), it falls through to generating a brand new master key, overwriting the existing encrypted key preference... If either `existingEncrypted` is present or `existingIv` is present without the other, throw `IllegalStateException("CORRUPTED_KEYSTORE_PREFS")` rather than silently overwriting."*

3. **Current Test & Analysis Status**:
   - `python test_docs_integrity.py` exits 0 (all 6 verification test suites passed 100%).
   - `C:\Other\Dev\flutter\bin\flutter.bat analyze` exits 0 (`No issues found! (ran in 10.0s)`).
   - `C:\Other\Dev\flutter\bin\flutter.bat test` exits 0 (`44/44 tests passed`).

---

## 2. Logic Chain

1. **Step 1 (Failure Impact Tracing)**:
   - When an Android application uses SQLCipher to encrypt its database, the database decryption key is derived once at creation.
   - If an error, OS interruption, or partial restore causes `existingIv` to be null while `existingEncrypted` is non-null (Observation 1), current code enters the generation branch (lines 224-237).
   - The generation branch produces a completely different 32-byte key and overwrites `PREF_ENCRYPTED_DB_KEY` in SharedPreferences.
   - Result: SQLCipher can no longer open `singwallet.db` (failing with `file is not a database`), and because the old ciphertext was overwritten, the original key cannot be recovered by any means.
2. **Step 2 (State Asymmetry Enforcement)**:
   - Both ciphertext (`PREF_ENCRYPTED_DB_KEY`) and IV (`PREF_DB_KEY_IV`) form an indivisible cryptogram unit.
   - Therefore, if `hasEncrypted != hasIv` or if either value is blank/corrupt, the only mathematically and architecturally sound response is to refuse to proceed: fail fast and throw `IllegalStateException("CORRUPTED_KEYSTORE_PREFS: ...")`.
3. **Step 3 (Hardware Key Decoupling)**:
   - If SharedPreferences contains key material, the wrapping key in `AndroidKeyStore` must already exist.
   - Generating a new hardware key when encrypted data is present (Observation 1, lines 195-211) will never decrypt the old data (AES-GCM tag mismatch).
   - Therefore, if prefs are present but `!keyStore.containsAlias(KEY_ALIAS)`, the system must throw `IllegalStateException("KEYSTORE_KEY_LOST: ...")` and refuse to overwrite the alias.
4. **Step 4 (Durability via `.commit()`)**:
   - Asynchronous `.apply()` in Observation 1 (line 235) introduces a race condition where the caller receives `rawKey`, encrypts the database, but the app crashes before the disk write completes.
   - Replacing `.apply()` with synchronous `.commit()` guarantees durability and allows validating the boolean return status before returning `rawKey` to the database layer.
5. **Step 5 (Orphan Database Protection)**:
   - If a database file already exists on disk (`singwallet.db` > 0 bytes) but SharedPreferences has no keys, generating a new random key would produce an incompatible key.
   - Throwing `ORPHAN_DATABASE_FOUND` prevents corrupting or overwriting an existing database file.

---

## 3. Caveats

1. **Read-Only Scope**:
   In accordance with the explorer role constraints, no direct modifications have been made to `NativeCaptureHostApiImpl.kt`. A clean, machine-applicable patch file has been authored at `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch`.
2. **Key Store Backup Exclusion in AndroidManifest**:
   Android hardware Keystore keys cannot be backed up to cloud services (Google Drive / Auto Backup). When `AndroidManifest.xml` is authored in packaging phases, `android:allowBackup="false"` or backup exclusion rules for `singwallet_sec_prefs.xml` should be configured to prevent restoring encrypted preferences to devices that lack the hardware Keystore key.
3. **Cross-Platform Parity**:
   iOS Keychain (`NativeCaptureHostApiImpl.swift`) does not suffer from this issue because the 32-byte key is stored directly in Keychain as an atomic item rather than wrapped and split into ciphertext/IV preferences.

---

## 4. Conclusion

- **Assessment**: The vulnerability identified in Finding 3 is critical to database integrity and must be resolved before proceeding to Milestone M1-A database implementation.
- **Recommended Solution**:
  1. Add strict state checking in `NativeCaptureHostApiImpl.kt`:
     - Throw `CORRUPTED_KEYSTORE_PREFS` if `hasEncrypted != hasIv` or either value is blank.
     - Throw `KEYSTORE_KEY_LOST` if prefs exist but Keystore alias is missing.
     - Throw `ORPHAN_DATABASE_FOUND` if `singwallet.db` exists without encryption preferences.
  2. Switch from `.apply()` to `.commit()` with explicit boolean verification (`PREFS_COMMIT_FAILED`).
  3. Validate decrypted key length to equal exactly 32 bytes (`MASTER_KEY_SIZE_BYTES`).
- **Artifacts Provided**:
  - Detailed report: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\report.md`
  - Git patch file: `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch`

---

## 5. Verification Method

1. **Verify Patch File**:
   Inspect `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch`.
2. **Apply & Verify Static Analysis**:
   ```powershell
   git apply c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2\master_key_guard.patch
   C:\Other\Dev\flutter\bin\flutter.bat analyze
   C:\Other\Dev\flutter\bin\flutter.bat test
   python test_docs_integrity.py
   ```
   All commands must exit with code 0.
3. **Invalidation Conditions**:
   If an existing preference key is ever modified or regenerated when only one of `encrypted_db_key` or `db_key_iv` is present, the verification has failed.
