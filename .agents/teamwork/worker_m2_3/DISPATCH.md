## 2026-10-23T01:53:24Z
Your working directory is c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_3.
You are worker_m2_3, a teamwork_preview_worker.

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Read the authoritative user request at:
c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md (specifically see section ## 2026-10-23T01:15:17Z for Milestone M2, Requirement R3).

Also read the architecture design and repository/provider contracts in:
- c:\Other\Projects\singwallet\.agents\teamwork\orchestrator_4\PROJECT.md
- c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_1\handoff.md
- lib/data/repositories/draft_repository.dart
- lib/presentation/providers/draft_providers.dart
- lib/features/deduplication/deduplication_engine.dart
- lib/core/native/native_bridge.g.dart

Task: Implement Milestone M2-3 (Draft Confirmation Screen & OCR BoundingBox Overlay).
Exclusive write ownership for this task:
- lib/presentation/screens/drafts/drafts_queue_screen.dart
- lib/presentation/screens/drafts/draft_confirmation_screen.dart
- lib/presentation/screens/drafts/widgets/ocr_bounding_box_overlay.dart
- lib/presentation/screens/drafts/widgets/smart_transaction_form.dart
- lib/presentation/screens/drafts/widgets/category_suggestion_card.dart
- lib/presentation/screens/drafts/widgets/deduplication_dialogs.dart

Implementation Requirements:
1. `DraftsQueueScreen` (`lib/presentation/screens/drafts/drafts_queue_screen.dart`):
   - Consumes `draftsQueueProvider`.
   - Displays list of pending drafts in `NEEDS_REVIEW` state with merchant name, amount preview, channel, and timestamp.
   - Tapping item navigates to `DraftConfirmationScreen(draftId: ...)`.
2. `OcrBoundingBoxOverlay` (`lib/presentation/screens/drafts/widgets/ocr_bounding_box_overlay.dart`):
   - Maps normalized `[0.0, 1.0]` coordinates to viewport without distortion or clipping using letterbox/pillarbox AspectRatio calculation.
   - Draws semi-transparent colored bounding box rectangles for detected text lines.
   - Interactive touch-to-fill: Tapping a bounding box invokes callback with recognized text to autofill into Merchant Name or Amount input fields.
   - Handles placeholder/mock canvas gracefully if local screenshot file is absent.
3. `SmartTransactionForm` (`lib/presentation/screens/drafts/widgets/smart_transaction_form.dart`):
   - 36pt prominent amount input with currency symbol (allows decimal input like "12.50", converts to integer cents).
   - Payment channel dropdown (WeChat, Alipay, Bank Card, Cash, etc.).
   - Transaction type selector (Expense, Income, Transfer, Refund).
   - Merchant name input field with clear button.
   - Transaction date/time picker.
   - Notes / project dropdown.
4. `CategorySuggestionCard` (`lib/presentation/screens/drafts/widgets/category_suggestion_card.dart`):
   - Displays AI/rule recommended category with icon, name, and confidence percentage (e.g. "餐饮 95% 置信度").
   - Quick one-tap accept or tap to open full category picker modal.
5. `DeduplicationDialogs` (`lib/presentation/screens/drafts/widgets/deduplication_dialogs.dart`):
   - Intercepts before commit via `DeduplicationEngine.evaluate(...)`:
     - Tier 3 active duplicate: Red blocking alert dialog ("发现完全相同订单号的已确认交易，禁止重复入账").
     - Tier 3 trash duplicate: Amber alert dialog ("此订单号曾被删除，存在于回收站中，是否直接恢复？").
     - Tier 4 24h heuristic duplicate: Secondary confirmation dialog ("24小时内发现相同金额的相似交易，是否确认这笔交易不是重复记录？") with [取消] and [继续入账] buttons.
6. `DraftConfirmationScreen`:
   - Integrates screenshot preview with `OcrBoundingBoxOverlay` on top, `CategorySuggestionCard`, and `SmartTransactionForm`.
   - "确认入账" (Commit) button: executes deduplication check, handles dialogs, calls `draftRepositoryProvider.commitDraft`, shows success feedback, and pops back to refresh queue.
   - "放弃草稿" (Discard) button: confirms and marks draft discarded.
7. Strict Typing:
   - Adhere to `strict-casts`, `strict-inference`, and `strict-raw-types`.

Verification:
- Run `flutter analyze` and ensure 0 errors, 0 warnings, 0 lints.
- Run `flutter test` and ensure all existing tests pass with 0 failures.
- Document implementation details and test commands in `c:\Other\Projects\singwallet\.agents\teamwork\worker_m2_3\handoff.md`.
- Send message to parent when done.
