# Handoff Report - spec_miner_survey_3

## 1. Observation
- Verified authoritative specifications across five key files:
  - `c:\Other\Projects\singwallet\.agents\teamwork\ORIGINAL_REQUEST.md`: lines 25-30 specify requirements R3 and R4 for milestone M1.
  - `c:\Other\Projects\singwallet\docs\跨平台架构与数据规范.md`: lines 147-339 define the 12 core tables and 11 indexes; lines 343-378 specify the 4-tier deduplication mechanism and accounting rules.
  - `c:\Other\Projects\singwallet\docs\Android实现方案.md`: lines 291-379 specify the OCR parsing pipeline, amount disambiguation, merchant normalization, and field evidence structures; lines 380-400 specify the classification rule hierarchy.
  - `c:\Other\Projects\singwallet\docs\iOS实现方案.md`: lines 425-471 detail iOS-specific OCR adaptations (status bar top < 0.06/0.075 filtering, home indicator top > 0.95 filtering, Vision coordinate conversion).
  - `c:\Other\Projects\singwallet\test_docs_integrity.py`: 445 lines of Python code verifying markdown syntax, Pigeon consistency, SQLite DDL/constraints, SWBK v1 cryptography, CSV injection protection, and coordinate normalization. Executed via `python test_docs_integrity.py` with exit code 0.
- Executed `where.exe flutter` and `where.exe dart`: Neither `flutter` nor `dart` was located in current system PATH. `winget.exe` is present and functional.

## 2. Logic Chain
- Step 1 (Observation -> Pipeline Design): `Android实现方案.md` lines 293-302 and `iOS实现方案.md` lines 428-449 define an 8-stage OCR parsing pipeline from raw `OcrDocument` to `drafts` entry. Status bar filtering (`top < 0.06`/`0.075`) and home bar filtering (`top > 0.95`) must occur first to remove false timestamps and numbers.
- Step 2 (Observation -> Disambiguation Rules): `Android实现方案.md` lines 336-343 prohibit using font size alone to infer payment amount, requiring labeled disambiguation (`实付`, `付款金额` vs `原价`, `优惠`, `余额`). Amounts must be converted into integer cents without floating-point math to avoid IEEE 754 precision drift.
- Step 3 (Observation -> Rule Precedence): `Android实现方案.md` lines 392-393 and `iOS实现方案.md` lines 481-482 define a strict 6-tier hierarchy: User manual choice > User explicit rules > Historical merchant mapping > Built-in keywords > AI suggestions > Fallback (`cat_other`). New learned rules apply only to future transactions and never alter history.
- Step 4 (Observation -> Anti-Duplicate Logic): `跨平台架构与数据规范.md` lines 361-378 specify four anti-duplicate tiers (Technical Idempotence -> SHA-256 Hash -> `confirmed_identifiers` Primary Key -> 24h heuristic). Tier 3 enforces hard blocking on unmasked platform transaction IDs, while Tier 4 issues warnings for user resolution ("同店同金额连续买两次").
- Step 5 (Observation -> Test Execution Architecture): SQLite constraints and pure Dart domain logic (OCR parsing, rule matching, amount conversions) can be executed without an emulator using `sqflite_common_ffi` or `sqlite3` in `flutter test` / `dart test`.
- Step 6 (Observation -> Python Test Integrity): `test_docs_integrity.py` requires all markdown code fences to be balanced (even count) and all bracket-parenthesis combinations to resolve to valid on-disk files.

## 3. Caveats
- Flutter SDK is not currently added to PATH in this shell environment. Execution of Flutter/Dart unit tests will require adding Flutter/Dart to PATH or running them in an environment where Flutter is installed.
- No live sample image files were included in the workspace; OCR testing must be driven by mocked `OcrDocument` structures mirroring real-world WeChat and Alipay receipts.

## 4. Conclusion
- Specifications for R3 (交易识别解析与分类规则引擎) and R4 (自动化测试套件与持续验证) are complete, unambiguous, and mathematically verifiable.
- A full feature inventory (30 features discovered, 18 edge cases analyzed, 9 automated test suites specified, and test runner recommendations) has been compiled into `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_3\report.md`.
- `test_docs_integrity.py` passes 100% with exit code 0.

## 5. Verification Method
- Execute docs integrity suite:
  ```powershell
  python test_docs_integrity.py
  ```
  Expected output: `ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%!`, exit code 0.
- Inspect full survey report:
  `c:\Other\Projects\singwallet\.agents\teamwork\spec_miner_survey_3\report.md`
- Invalidation condition: Any failure in `test_docs_integrity.py` or discrepancies between report formulas and `docs/` specifications.
