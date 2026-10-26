# Handoff Report — explorer_m2_1

**Milestone**: Milestone M2 (Core Business UI & Riverpod State Bus)  
**Agent**: `explorer_m2_1` (`teamwork_preview_explorer`)  
**Date**: 2026-10-23  

---

## 1. Observation

1. **`pubspec.yaml`**:
   - `flutter_riverpod: ^2.5.1` is declared as a direct dependency (line 13).
   - `sqflite: ^2.3.3+1` and `sqflite_common_ffi: ^2.3.3` are present (lines 14-15).
   - `intl: ^0.19.0`, `crypto: ^3.0.3`, `pigeon: ^22.7.0` are present.
2. **`lib/main.dart`**:
   - Root widget is already wrapped in `ProviderScope(child: SingWalletApp())` (lines 7-9).
   - App uses `ThemeData(useMaterial3: true)` (line 23).
   - Currently displays a static placeholder page `SingWalletHomePage` (lines 30-70).
3. **`lib/data/database/schema.dart`**:
   - 12 tables defined: `capture_jobs`, `drafts`, `accounts`, `categories`, `projects`, `tags`, `transactions`, `transaction_metadata`, `transaction_tags`, `refund_links`, `classification_rules`, `confirmed_identifiers` (lines 250-263).
   - 11 indices defined: `idx_capture_jobs_hash`, `idx_capture_jobs_state`, `idx_drafts_saved_tx`, `idx_tx_occurred_on`, `idx_tx_category`, `idx_tx_deleted_at`, `idx_tx_project`, `idx_tx_account`, `idx_transaction_tags_tag`, `idx_refund_original`, `idx_confirmed_identifiers_tx` (lines 266-278).
   - `transactions.category_id` has `FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE RESTRICT` (line 138).
   - `transactions.amount_minor` has `CHECK (amount_minor > 0)` (line 134).
   - Tables are created empty in `onCreate`; no initial seeding exists in `AppSchema` or `AppDatabase`.
4. **`lib/data/database/app_database.dart`**:
   - Singleton `AppDatabase.instance` (line 16).
   - Public methods: `initializeFfi()`, `get database`, `open({String? customPath})`, `openInMemory({DatabaseFactory? factory})`, `close()`, `setDatabaseFactory()`, `reset()`.
   - No query methods, no reactive streams, no event buses (lines 1-136).
5. **`lib/data/database/transaction_manager.dart`**:
   - Public methods:
     - `commitDraft(CommitDraftRequest request, {DatabaseExecutor? customExecutor})` (lines 107-271) - atomic across 7 tables.
     - `discardDraft(String draftId)` (lines 275-294).
     - `softDeleteTransaction(String transactionId, ...)` (lines 297-308).
     - `restoreFromTrash(String transactionId, ...)` (lines 312-362).
     - `permanentDeleteTransaction(String transactionId, ...)` (lines 367-375).
     - `purgeExpiredTrash({int retentionDays = 30, ...})` (lines 379-390).
     - `getMonthlySummary(String yearMonth, ...)` (lines 393-405) - calls `SoftDeleteManager.calculateMonthlySummary`.
   - No reactive streams or query lists for transactions, drafts, accounts, or categories.
6. **`lib/data/database/soft_delete_manager.dart`**:
   - `getTrashBinTransactions(db)` (lines 132-140) queries `transactions WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC`.
   - `calculateMonthlySummary(db, {required String startDate, required String endDate})` (lines 150-189) computes `totalExpenseMinor`, `totalRefundMinor`, `netExpenseMinor`, but strictly ignores `income` transactions.
7. **`lib/features/deduplication/deduplication_engine.dart`**:
   - `checkTier3PlatformId(PlatformIdentifier identifier)` (lines 286-329):
     - Only executes if `identifier.isEligibleForHardDedup` (requires `completeValue.trim().isNotEmpty` and `completeness == IdentifierCompleteness.complete`).
     - Queries `confirmed_identifiers` join `transactions`.
     - Returns `Tier3Result.trashBinDuplicate` if `deleted_at != null`, or `Tier3Result.activeDuplicate` if `deleted_at == null`, or `Tier3Result.miss()`.
   - `checkTier4Fuzzy({required String merchantRaw, String? merchantNormalized, required int amountMinor, required String occurredOn, String? occurredAt})` (lines 336-419):
     - Queries `transactions WHERE deleted_at IS NULL AND amount_minor = ? AND occurred_on BETWEEN ? AND ?` (candidate date +/- 1 day).
     - Filters by merchant name match (raw/norm permutations) and checks timestamp difference <= 24 hours.
     - Returns `Tier4Result.suspected` with candidate transaction IDs and maps, or `Tier4Result.clean()`.
   - `evaluate(...)` aggregates across all 4 tiers (lines 422-461).
8. **`lib/features/recognition/ocr_pipeline.dart` & models**:
   - `OcrBoundingBox` has normalized coords `left, top, width, height` in $[0.0, 1.0]$, origin at top-left.
   - `FieldEvidence` (lines 5-65 in `field_evidence.dart`) contains `rawText`, `matchedSubstring`, `boundingBox`, `confidence`, `source`.
   - `OcrParsingPipeline.process()` (lines 28-244) returns `ParsedDraftResult`.
   - `ParsedDraftResult.toDraftEntity()` (lines 146-159 in `parsed_draft_result.dart`) serializes candidate fields and field evidence to JSON for storage in the `drafts` table.
9. **Test & Static Analysis Baseline**:
   - Running `flutter test` executed all 297 tests across database, deduplication, recognition, and classification: `All tests passed! 00:03 +297`.
   - Running `flutter analyze` completed with `No issues found! (ran in 7.5s)`.

---

## 2. Logic Chain

1. From Observation 1 & 2: `flutter_riverpod: ^2.5.1` and `ProviderScope` are already configured in `pubspec.yaml` and `main.dart`. The foundation for state management is complete; no new packages or root refactorings are required.
2. From Observation 3 & 4: `AppDatabase` creates 12 tables and 11 indices, but provides no query methods or reactive streams.
3. From Observation 5 & 6: `TransactionManager` provides atomic write operations (`commitDraft`, `softDeleteTransaction`, `restoreFromTrash`, `permanentDeleteTransaction`), but does not provide queries for UI filtering (date ranges, accounts, projects, categories, keywords, types) or income aggregation.
4. From Observation 3: `transactions.category_id` has `FOREIGN KEY(...) REFERENCES categories(id) ON DELETE RESTRICT`. Because tables are created empty, inserting a transaction with `cat_food` or `cat_other` fails unless those rows exist in `categories`. Thus, a database seeder for default categories (`cat_food`, `cat_transport`, etc.) and accounts (`acc_wechat`, `acc_alipay`, etc.) is an absolute prerequisite.
5. From Observation 7: `DeduplicationEngine.evaluate()` exposes `tier3` and `tier4` results. Tier 3 distinguishes between active transactions (requiring a blocking alert in the UI) and trash-bin transactions (requiring a restore prompt dialog). Tier 4 detects matching transactions within 24 hours (requiring a secondary confirmation dialog in the UI).
6. From Observation 8: `FieldEvidence` preserves `OcrBoundingBox` normalized coordinates $[0.0, 1.0]$. A Flutter canvas or `CustomPainter` / `Stack` can directly map these coordinates to pixel rects $(\text{left} \times W, \text{top} \times H, \text{width} \times W, \text{height} \times H)$ to render interactive highlights for touch-to-fill into merchant/amount form fields.
7. From Observation 9: The existing 297 tests and 0 analysis issues establish a rock-solid baseline. Milestone M2 implementation must maintain this 100% pass rate and 0 lint issues.

---

## 3. Caveats

1. **Native Screen Capture on Desktop**: Pigeon calls (`NativeCaptureHostApi`) will fail on Windows test runners if invoked without mock bridges. For Widget testing and local desktop execution, mocks or test fixtures for `NativeBridgeService` must be used.
2. **Image Loading in Draft Confirmation**: The `private_image_ref` in `capture_jobs` points to a relative/sandbox image path. In tests, draft confirmation widgets must handle placeholder or simulated image rendering when local file paths do not exist.
3. **No Uninvestigated Core Modules**: All five modules requested in the prompt (`lib/data/`, `lib/features/deduplication/`, `lib/features/recognition/`, `lib/features/classification/`, `pubspec.yaml`) were inspected line by line.

---

## 4. Conclusion

1. **Architecture Path**: Create a clean repository layer (`TransactionRepository`, `DraftRepository`, `CategoryRepository`, `AccountRepository`, `RuleRepository`) on top of `AppDatabase` and domain managers to provide queries, filtering, and seeding.
2. **Riverpod State Bus**: Build Notifiers (`TransactionsNotifier`, `DraftsQueueNotifier`, `CategoriesNotifier`, `AccountsNotifier`, `RulesNotifier`, `TransactionFilterNotifier`) that listen to or trigger re-queries after mutations.
3. **UI Implementation Scope**:
   - `TransactionsScreen`: Monthly summary board (including income!), grouped date list, filter bottom sheet, soft delete & undo snackbars, recycling bin dialog.
   - `DraftConfirmationScreen`: Interactive bounding box overlay on screenshot canvas with click-to-fill, edit form, suggested category card, and Tier 3 / Tier 4 duplicate intercept dialogs.
   - `RulesAndAccountsScreen`: 6-tier classification rules list with drag-and-drop priority ordering, account balances, project management, and refund link picker modal.
   - `DatabaseSeeder`: Seed default categories and accounts on first launch to satisfy foreign key integrity constraints.

---

## 5. Verification Method

1. **Verify Report & Files**:
   - Inspect `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m2_1\report.md`
   - Inspect `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m2_1\handoff.md`
2. **Verify Existing Tests**:
   ```powershell
   flutter test
   ```
   *Expected*: All 297 tests pass with exit code 0.
3. **Verify Static Analysis**:
   ```powershell
   flutter analyze
   ```
   *Expected*: 0 issues found.
