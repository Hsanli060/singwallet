# BRIEFING — 2026-10-22T10:02:30Z

## Mission
Investigate and propose concrete fix strategy for Android Keystore state guarding in NativeCaptureHostApiImpl.kt to prevent silent database key regeneration and corruption.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Other\Projects\singwallet\.agents\teamwork\explorer_m0_retry_2
- Original parent: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Milestone: m0_retry_2

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Formulate strict state checking: if ciphertext exists without IV or vice-versa, do not silently regenerate a new key; handle corruption safely and ensure an existing key is never overwritten on partial read.
- Provide exact code diff / recommendations.

## Current Parent
- Conversation ID: 0be8f589-cb64-4c3b-aed0-2d1a129de39c
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeCaptureHostApiImpl.kt` (`getOrCreateMasterDbKey`)
  - `android/app/src/main/kotlin/com/singwallet/app/bridge/NativeBridge.g.kt` (`wrapError`, Pigeon channel bindings)
  - `ios/Runner/Plugins/NativeCaptureHostApiImpl.swift` (Keychain master key parity)
  - `lib/core/native/native_bridge_service.dart` (`getOrCreateDatabaseKey` exception mapping)
  - `test/core/native/pigeon_stress_challenge_test.dart` (PlatformException handling)
  - `reviewer_m0_2/report.md` & `handoff.md` (Finding 3 analysis)
- **Key findings**:
  - `getOrCreateMasterDbKey()` silently regenerates a new key whenever `existingEncrypted != null && existingIv != null` is false, overwriting existing preferences and permanently corrupting SQLite databases.
  - Keystore wrapping key was being checked/generated before preferences were verified, masking Keystore key loss.
  - Asynchronous `.apply()` created race conditions where DB could be encrypted before keys reached disk.
  - Formulated 7-state truth table and complete defensive solution.
- **Unexplored areas**:
  - None within Android Keystore state guarding scope.

## Key Decisions Made
- Guard partial SharedPreferences state with fail-fast `IllegalStateException("CORRUPTED_KEYSTORE_PREFS: ...")`.
- Guard missing Keystore wrapping key with `IllegalStateException("KEYSTORE_KEY_LOST: ...")`.
- Guard orphaned database file on disk with `IllegalStateException("ORPHAN_DATABASE_FOUND: ...")`.
- Replace asynchronous `.apply()` with synchronous atomic `.commit()`, verifying boolean return.
- Authored unified patch file `master_key_guard.patch` for clean worker application.

## Artifact Index
- `DISPATCH.md` — Incoming dispatch instructions
- `progress.md` — Liveness heartbeat and status log
- `master_key_guard.patch` — Unified diff patch for NativeCaptureHostApiImpl.kt
- `report.md` — Comprehensive threat model, truth table, and fix recommendations
- `handoff.md` — 5-component handoff report
