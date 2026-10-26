# Handoff Report: OCR Transaction Parsing Pipeline Blueprint (Milestone M1-B: Features F19–F26)

**Agent:** `explorer_m1b_1`  
**Parent Agent:** `a14d1a00-adfd-46db-a470-136d68156a40`  
**Date:** 2026-10-22  
**Handoff Type:** Hard (Task complete)

---

## 1. Observation
1. **Pigeon IDL & Native Bridge Contract**:
   - In `pigeons/native_bridge.dart` (lines 42–83) and `lib/core/native/native_bridge.g.dart` (lines 84–165):
     `OcrBoundingBox` is defined with `left`, `top`, `width`, `height` in normalized `[0.0, 1.0]` coordinates with top-left origin.
     `OcrTextLine` contains `text`, `boundingBox`, and optional `confidence` (0.0 – 1.0).
     `OcrDocument` contains `captureId`, `lines`, `engineIdentifier`, and `processTimeMs`.
2. **Noise Filtering Geometry & System Chrome**:
   - In `docs/iOS实现方案.md` lines 453–457:
     "对屏幕顶部垂直比例 `top < 0.06`（动态岛机型为 `top < 0.075`）区域内的文本，一律打上「系统状态栏」标记，禁止将其中的数字误识别为交易时间或金额。"
     "对底部 `top > 0.95` 的 Home 条区域进行类似边界裁剪。"
   - In `docs/Android实现方案.md` lines 306–316:
     Coordinates are mapped from ML Kit Rect into `[0.0, 1.0]` normalized floats.
3. **Amount Rules & Semantic Disambiguation**:
   - In `docs/Android实现方案.md` lines 336–343:
     "不把字号最大的数字直接视为本笔支出；它也可能是余额、原价或累计金额。"
     "「实付 / 支付金额」优先；原价、优惠、余额、积分、月累计分别识别。"
     "页面显示「待支付」「处理中」「失败」时，不能生成可直接确认的已支付支出。"
     "首版仅支持人民币。币种不明或明确为外币时要求用户确认处理。"
     "首版允许无金额的识别结果留为待处理，但禁止将其保存为零元正式消费。"
4. **Relational Database DDL & Schema Constraints**:
   - In `docs/跨平台架构与数据规范.md` lines 165–176 and 233–282:
     `drafts` table has `id`, `capture_id`, `candidate_fields` (JSON text), `field_evidence` (JSON text), `validation_issues` (JSON array text), `duplicate_candidates` (JSON array text).
     `transactions` table has `amount_minor INTEGER NOT NULL CHECK (amount_minor > 0)`, `occurred_on TEXT NOT NULL`, `occurred_at TEXT`, `event_time_source TEXT NOT NULL`, `event_time_precision TEXT NOT NULL`, `payment_channel TEXT NOT NULL`.
     `transaction_metadata` table has `original_amount_minor`, `discount_minor`, `fee_minor`, `payment_status`, `platform_transaction_no`, `merchant_order_no`, `identifier_completeness` (`NONE`, `COMPLETE`, `MASKED`, `TRUNCATED`, `UNRELIABLE`).
5. **Existing Codebase State & Test Invariants**:
   - Command `& "C:\Other\Dev\flutter\bin\flutter.bat" test` exited code 0 with 145/145 tests passing.
   - Command `python test_docs_integrity.py` exited code 0 verifying all 6 deep consistency suites.
   - `lib/features/deduplication/deduplication_engine.dart` (lines 47–65) defines `PlatformIdentifier` with `completeness == IdentifierCompleteness.complete` gating Tier 3 hard deduplication.

---

## 2. Logic Chain
1. From **Observation 1 & 2**, because native OCR outputs normalized top-left `[0.0, 1.0]` coordinates for each line, `NoiseFilter` can safely eliminate status bar text (`top < 0.06` or `top < 0.075` for dynamic island) and home indicator lines (`top > 0.95`) purely based on geometry before regex matching, preventing status bar clocks (e.g. `09:41`) and battery percentages from polluting transaction times or amounts.
2. From **Observation 3**, financial screenshots often include multiple numbers (original price, discount, service fee, balance, and paid amount). To ensure correctness, `AmountParser` must implement a 2-tier semantic hierarchy: explicit labeled extraction ("实付", "实付款", "支付金额", "扣款") takes highest priority over unlabeled amounts. Original amount, discount, and fee are partitioned into `original_amount_minor`, `discount_minor`, and `fee_minor`, while account balances and monthly totals are explicitly discarded.
3. From **Observation 3 & 4**, because SQLite enforces `CHECK (amount_minor > 0)` and zero amounts are prohibited as formal expenses, any detected amount equal to zero must trigger `ValidationIssueCode.zeroAmountNotPermitted`, while missing amounts trigger `ValidationIssueCode.missingAmount`.
4. From **Observation 3**, optical character recognition frequently introduces visual character confusions in numbers (e.g. `O`/`o` for `0`, `l`/`I`/`|` for `1`, `S`/`s` for `5`, `B` for `8`). By running a context-aware character repair pass on extracted numeric tokens prior to parsing through `CurrencyUtils.parseToMinorUnits`, parsing resilience is maximized without risking false positives on non-numeric text.
5. From **Observation 4 & 5**, the deduplication engine requires a clean distinction between full unbroken platform transaction IDs and masked/truncated IDs. Only `COMPLETE` IDs can be registered into `confirmed_identifiers` to hard-block duplicates. `OrderIdParser` must evaluate character completeness, length ($\ge 16$ digits for platform IDs), and absence of masking characters (`*`, `x`), assigning `IdentifierCompleteness.complete`, `masked`, `truncated`, or `unreliable`.
6. From **Observation 4**, `drafts` table stores `candidate_fields`, `field_evidence`, and `validation_issues` as JSON strings. `ParsedDraftResult` in `ocr_pipeline.dart` serves as the unifying domain model, orchestrating Stages 1–8 and providing serialization methods (`toCandidateFieldsJson()`, `toFieldEvidenceJson()`, `toValidationIssuesJson()`) that cleanly plug into `Draft` persistence and `DeduplicationEngine.evaluate(...)`.

---

## 3. Caveats
1. **Dynamic Island Detection**: In the absence of native hardware model metadata passing down device notch type, the noise filter employs a heuristic: if any line with `top < 0.075` matches status bar indicators (clock `\d{1,2}:\d{2}`, cellular/carrier `5G`/`4G`, battery percentage), it activates the dynamic island `0.075` threshold; otherwise it uses the standard `0.06` cutoff.
2. **AI Recommendation Pipeline**: This blueprint covers deterministic local OCR rule extraction (F19–F26). Cloud AI semantic completion (optional P1 feature) is intentionally decoupled as an extension that accepts minimized OCR text and returns the same JSON schema.
3. **No Code Written to `lib/` in Investigation Phase**: In strict adherence to the Explorer archetype, no source files were created or modified in `lib/` or `test/`. The blueprint is documented in `report.md`.

---

## 4. Conclusion
The technical blueprint for the OCR Transaction Parsing Pipeline (Milestone M1-B: Features F19–F26) is fully designed, documented, and production-ready in `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_1\report.md`. It provides complete class contracts, regular expressions, normalization dictionaries, error catalogs, and test specifications for:
- F19: Noise Filtering (`noise_filter.dart`)
- F20: Channel & Status Parsing (`channel_status_parser.dart`)
- F21: Amount Disambiguation & Repair (`amount_parser.dart`)
- F22: Merchant Normalization (`merchant_normalizer.dart`)
- F23: Time Extraction (`time_parser.dart`)
- F24: Order ID & Completeness (`order_id_parser.dart`)
- F25: Field Evidence Recording (`field_evidence.dart`, `validation_issue.dart`)
- F26: Draft Assembly Pipeline (`ocr_pipeline.dart`)

---

## 5. Verification Method
1. Inspect the comprehensive blueprint document:
   `view_file` on `c:\Other\Projects\singwallet\.agents\teamwork\explorer_m1b_1\report.md`.
2. Verify all current tests pass:
   Run `& "C:\Other\Dev\flutter\bin\flutter.bat" test` (145/145 pass, Exit code 0).
3. Verify documentation and architectural integrity:
   Run `python test_docs_integrity.py` (All 6 test suites pass, Exit code 0).
4. Verify downstream worker implementability:
   Review class definitions and method signatures in `report.md` Section 10 and 12 against `lib/data/models/draft.dart` and `lib/features/deduplication/deduplication_engine.dart`.
