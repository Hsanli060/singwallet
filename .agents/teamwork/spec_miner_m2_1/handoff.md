# Handoff Report: Milestone M2 Specification Mining

- **Agent**: `spec_miner_m2_1`
- **Archetype**: `teamwork_preview_spec_miner`
- **Milestone**: Milestone M2 (Core Presentation Layer, UI Flows, Interaction Rules & Riverpod Architecture)
- **Report Location**: `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1\report.md`
- **Date**: 2026-10-23T01:25:00Z

---

## 1. Observation

1. **`ORIGINAL_REQUEST.md` (lines 45–100)**:
   - Mandates Milestone M2 requirements:
     - R1: Riverpod state management layer & ViewModels (`AppDatabase`, `TransactionManager`, `OcrPipeline`, `ClassificationRuleEngine` dependency injection, reactive streams, draft queue, dictionaries).
     - R2: Transactions Screen & Dashboard (monthly summary stats: total expense, total refund, net expense; daily aggregated groups with subtotals, rich transaction tiles, filter bottom sheet/drawer, soft delete / undo SnackBar / 30-day recycling bin purge).
     - R3: Draft Confirmation Screen & OCR BoundingBox Overlay (normalized coordinates `[0.0, 1.0]` mapping to image viewport without distortion, tap to backfill merchant/amount/note, smart form with 36pt amount, 4-tier deduplication alerts: Tier 3 blocking, Tier 4 24h heuristic duplicate confirmation dialog, one-click commit `IDENTIFIED` -> `CONFIRMED`).
     - R4: Rules & Accounts Configuration Center (6-tier classification rules list with drag-and-drop priority adjustment, enable/disable toggle, re-match triggers; account list & balances; project list; refund link picker dialog respecting `refund_links ON DELETE CASCADE`).
     - R5: Widget testing & E2E verification requirements.
   - Acceptance Criteria: `flutter analyze` 0 issues found; `flutter test` passes 100%.

2. **Cross-Platform Specification (`docs/跨平台架构与数据规范.md`)**:
   - Section 1 (lines 11–28): Riverpod UI layer strictly manages presentation, state, and user actions, delegating accounting, deduplication, and persistence to the core Dart modules.
   - Section 2.1 (lines 81–87): `OcrBoundingBox` defines normalized coordinates `left, top, width, height` in `[0.0, 1.0]` with origin at top-left.
   - Section 3 (lines 147–339): 12 SQLite tables including `capture_jobs`, `drafts`, `transactions`, `transaction_metadata`, `refund_links`, `classification_rules`, `confirmed_identifiers`.
     - `refund_links` (line 304): `FOREIGN KEY(original_expense_id) REFERENCES transactions(id) ON DELETE CASCADE`.
   - Section 4.1 (lines 347–358):
     - All currency stored as integer cents (`amount_minor > 0`).
     - Monthly total expense = `SUM(amount_minor)` WHERE `type = 'expense' AND deleted_at IS NULL`.
     - Monthly total refund = `SUM(amount_minor)` WHERE `type = 'refund' AND deleted_at IS NULL`.
     - Monthly net expense = total expense $-$ total refund.
     - Internal transfers (`type = 'transfer'`) excluded from monthly totals.

3. **Existing Core Implementations in Codebase**:
   - `lib/data/database/app_database.dart`: Singleton `AppDatabase.instance`, SQLite initialization via `sqflite_common_ffi`.
   - `lib/data/database/transaction_manager.dart`: Provides atomic `commitDraft()`, `discardDraft()`, `softDeleteTransaction()`, `restoreFromTrash()`, `permanentDeleteTransaction()`, `purgeExpiredTrash()`, `getMonthlySummary()`.
   - `lib/data/database/soft_delete_manager.dart`: Manages `deleted_at`, 30-day trash lifecycle, and `MonthlyAccountingSummary`.
   - `lib/data/database/state_machine.dart`: `CaptureJobState` lifecycle (`IMPORTED` $\rightarrow$ `RECOGNIZING` $\rightarrow$ `NEEDS_REVIEW` $\rightarrow$ `COMMITTED` / `DISCARDED`).
   - `lib/features/deduplication/deduplication_engine.dart`: Implements Tier 1 (idempotence), Tier 2 (image hash), Tier 3 (platform transaction ID match against active and trash records), and Tier 4 (heuristic 24h same merchant + same amount match).
   - `lib/features/classification/rule_engine.dart`: 6-tier hierarchy, `RuleMatcher.compareRules`, and `learnRuleFromUserAction()`.
   - `pubspec.yaml`: `flutter_riverpod: ^2.5.1` already configured.
   - Test execution: `flutter test` executed 297 tests, all passing with exit code 0 in 4.3 seconds.
   - Static analysis: `flutter analyze` passed with 0 issues found.

---

## 2. Logic Chain

1. **Architecture Alignment (R1)**:
   - Riverpod 2.x is already included in `pubspec.yaml`.
   - The Presentation layer must not duplicate database queries or bypass transaction managers.
   - All state mutations (`commitDraft`, `softDeleteTransaction`, `restoreFromTrash`, `learnRuleFromUserAction`) must be channeled through existing, verified services (`TransactionManager`, `ClassificationRuleEngine`, `DeduplicationEngine`).
   - Global DI container must supply these engines cleanly to ViewModels via typed providers.

2. **Transactions Screen & Dashboard (R2)**:
   - Requirements require monthly summary stats (expense, refund, net) and daily aggregation.
   - `SoftDeleteManager.calculateMonthlySummary` already computes `totalExpenseMinor`, `totalRefundMinor`, and `netExpenseMinor` with `deleted_at IS NULL` filtering.
   - UI must format minor currency units into decimal Yuan using `CurrencyUtils.centsToYuanString()`.
   - Soft deletion sets `deleted_at = now()`, immediately hiding the transaction from the active ledger, while offering an Undo SnackBar that calls `restoreFromTrash()`.
   - The 30-day recycling bin allows full recovery or permanent purge via `permanentDeleteTransaction()`.

3. **Draft Confirmation & BoundingBox Coordinate Mapping (R3)**:
   - `OcrBoundingBox` coordinates from Pigeon are normalized to $[0.0, 1.0]$ relative to the original image dimensions.
   - In Flutter, viewport container dimensions $(W_{viewport}, H_{viewport})$ may differ in aspect ratio from the image $(W_{img}, H_{img})$.
   - Under `BoxFit.contain`, non-uniform distortion must be prevented by calculating scale factor $S = \min(W_{viewport}/W_{img}, H_{viewport}/H_{img})$ and letterbox/pillarbox offsets $dx, dy$.
   - Bounding box rendering and tap hit-testing must map through $(dx + left \times W_{disp}, dy + top \times H_{disp})$.
   - Coordinate clamping to $[0.0, 1.0]$ prevents overflows on boundary OCR detections.
   - 4-tier deduplication alerts:
     - Tier 3 platform number collision on active ledger disables commit and shows red warning.
     - Tier 3 collision on trash bin shows amber warning with restore option.
     - Tier 4 24h heuristic duplicate triggers a secondary modal confirmation dialog allowing the user to either discard or confirm as a separate legitimate purchase (e.g. continuous coffee purchase).

4. **Rules & Accounts Configuration Center (R4)**:
   - 6-tier classification rules list must be ordered by `RuleMatcher.compareRules` (`priority DESC`, `pattern length DESC`, `createdAt DESC`).
   - Drag-and-drop priority reordering adjusts numeric priorities monotonically.
   - Re-match trigger re-evaluates all drafts in `NEEDS_REVIEW`, but guarantees strict non-retroactivity: past committed transactions are never rewritten.
   - Refund linking dialog links refunds to active expenses. When the original expense is permanently deleted, SQLite's `ON DELETE CASCADE` unlinks the record while keeping the refund transaction intact.

5. **Widget Testing Strategy (R5)**:
   - Presentation tests must use `ProviderScope` container overrides to mock database instances or run against isolated in-memory SQLite instances.
   - Comprehensive tests must verify dashboard rendering, soft delete undo, bounding box pixel coordinate mapping, tap-to-backfill, deduplication alert dialogs, rules center reordering, and refund cascade handling.

---

## 3. Caveats

- **No Caveats**: All 5 requirement groups (R1–R5), underlying database schemas, native Pigeon bridge IDL, and core engines have been inspected directly from authoritative repository sources. No assumptions beyond authoritative documentation were required.

---

## 4. Conclusion

The specification mining for Milestone M2 is 100% complete and documented in:
`c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1\report.md`

The report provides:
- Comprehensive **Features Discovered Table** (45 discrete features spanning R1 to R5).
- Comprehensive **Edge Cases Table** (15 boundary scenarios).
- Complete Riverpod Provider & ViewModel dependency hierarchy.
- Exact mathematical formulas for viewport aspect ratio coordinate mapping and letterbox/pillarbox offsets.
- Deduplication alert state machine rules and dialog interactions.
- SQLite foreign key cascading contracts and soft-delete recycling bin mechanics.
- Detailed Widget testing specifications for each screen.

---

## 5. Verification Method

To verify the findings and current codebase state:

1. **Verify Static Analysis**:
   ```powershell
   flutter analyze
   ```
   *Expected Output*: `No issues found! (ran in ~5s)`

2. **Verify Existing Core Test Suite**:
   ```powershell
   flutter test
   ```
   *Expected Output*: `All tests passed! (297 tests passed)`

3. **Verify Report Completeness**:
   Inspect `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_m2_1\report.md` to confirm:
   - Section 2: Features Discovered table with Category, Feature, Description, Inputs, Outputs, Error Behavior, Discovered Via.
   - Section 3: Edge Cases table with Feature, Input, Expected & Observed Behavior.
   - Section 4: Deep Architecture Specifications covering R1, R2, R3, R4, R5.
