# Project: SingWallet Core Engineering (M0 + M1)

## Architecture
SingWallet implements a high-reliability, offline-first personal financial transaction and ledger management system with native camera/share ingestion and automated OCR parsing.

### Clean Layering & Boundary Separation
1. **Platform Native Layer (Android / iOS)**:
   - Hardware security: Android Keystore / iOS Keychain (AES-256 SQLCipher database key derivation)
   - Capture sources: System Share Sheet, Photo Picker, Quick Settings Tile / Shortcuts
   - Native OCR: Android Google ML Kit Text Recognition v2, iOS Apple Vision Framework
   - Coordinate normalization: Converts platform-specific coordinates to normalized `[0.0, 1.0]` top-left origin bounding boxes
   - Low-memory streaming: Share Extension operates below 120MB Jetsam limit, passing file descriptors or references rather than raw bitmaps

2. **Native Bridge Interface (Pigeon IDL)**:
   - Defined in `pigeons/native_bridge.dart`
   - Generated code: `lib/core/native/native_bridge.g.dart`, `android/.../NativeBridge.g.kt`, `ios/.../NativeBridge.g.swift`, and `test/.../native_bridge_test.g.dart`
   - Typed Host API (`NativeCaptureHostApi`) and Flutter API (`NativeCaptureFlutterApi`)

3. **Core Domain & Persistence Layer (Flutter / Dart)**:
   - Storage: SQLite with full relational constraints (`FOREIGN KEY`, `CHECK (amount_minor > 0)`, `UNIQUE`)
   - 12 core tables and 11 specialized performance B-tree indices
   - Integer minor currency units (cents/分) for 100% precision without IEEE 754 float drift
   - 4-tier deduplication engine (Technical Idempotence -> Image SHA-256 -> Platform ID hard check -> 24h heuristic fuzzy check)
   - Deterministic ingestion task state machine (`IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED`)
   - 8-stage OCR parsing pipeline (Status bar noise filtering, amount disambiguation, merchant cleaning, date attribution)
   - 6-tier classification rule engine with wildcards and regex matching

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Flutter Scaffold Setup | Standard Flutter project configuration (`pubspec.yaml`, `analysis_options.yaml`, directory hierarchy) | M0 (DONE) | Survey (Miner 1) |
| 2 | Pigeon IDL Specification | Import `dart:typed_data`, configure PigeonOptions targets | M0 (DONE) | Survey (Miner 1) |
| 3 | Pigeon Code Generation | Generate Dart, Kotlin, Swift bridge files with zero static errors | M0 (DONE) | Survey (Miner 1) |
| 4 | Android Native Bridge | Implement `NativeCaptureHostApiImpl.kt` and register in `MainActivity.kt` | M0 (DONE) | Survey (Miner 1) |
| 5 | iOS Native Bridge | Implement `NativeCaptureHostApiImpl.swift` and register in `AppDelegate.swift` | M0 (DONE) | Survey (Miner 1) |
| 6 | Coordinate Normalization | ML Kit (top-left) & Vision (bottom-left) to `[0.0, 1.0]` box normalization | M0 (DONE) | Survey (Miner 1) |
| 7 | 12 Core SQLite Tables Schema | DDL for all 12 tables with constraints, nullability, default values | M1-A (DONE) | Survey (Miner 2) |
| 8 | 11 Performance Indices | Specialized B-tree indices covering hash, state, draft, dates, categories, refund, IDs | M1-A (DONE) | Survey (Miner 2) |
| 9 | Foreign Key Cascades | `refund_links ON DELETE CASCADE` unlinking, `parent_id SET NULL`, `RESTRICT` | M1-A (DONE) | Survey (Miner 2) |
| 10 | Integer Cent Currency Storage | Strict `INTEGER` minor units (`amount_minor > 0` CHECK), no float loss | M1-A (DONE) | Survey (Miner 2) |
| 11 | Tier 1 Technical Idempotence | `origin_draft_id UNIQUE` constraint & draft-to-transaction deduplication | M1-A (DONE) | Survey (Miner 2) |
| 12 | Tier 2 Same-Image SHA-256 Check | Ingestion image SHA-256 hash match in `capture_jobs` | M1-A (DONE) | Survey (Miner 2) |
| 13 | Tier 3 Platform Transaction ID Check | `confirmed_identifiers` compound PK hard deduplication | M1-A (DONE) | Survey (Miner 2) |
| 14 | Tier 4 Heuristic Fuzzy Match | Same merchant + amount within 24h soft duplicate warning | M1-A (DONE) | Survey (Miner 2) |
| 15 | Task State Machine | `IMPORTED` -> `RECOGNIZING` -> `NEEDS_REVIEW` -> `COMMITTED` / `FAILED` / `DISCARDED` | M1-A (DONE) | Survey (Miner 2) |
| 16 | Atomic Draft Commitment | SQLite transaction executing draft commit across multiple tables | M1-A (DONE) | Survey (Miner 2) |
| 17 | 30-Day Soft Delete Trash Bin | `deleted_at` soft delete & recovery preserving dedup identifiers | M1-A (DONE) | Survey (Miner 2) |
| 18 | Monthly Date Attribution | Financial reporting based on `occurred_on` date, net expense offset | M1-A (DONE) | Survey (Miner 2) |
| 19 | OCR Noise Filtering | Screen top status bar (`top < 0.06/0.075`) and home bar (`top > 0.95`) filtering | M1-B (DONE) | Survey (Miner 3) |
| 20 | Channel & Status Parsing | Recognize payment channels (`wechat`, `alipay`) and status (`SUCCESS`, `PENDING`, `FAILED`) | M1-B (DONE) | Survey (Miner 3) |
| 21 | Labeled Amount Disambiguation | Prioritize 实付 over 原价/优惠/余额, OCR character fix (O->0), iterative convergence | M1-B (DONE) | Survey (Miner 3) |
| 22 | Merchant Normalization | Extract `merchant_raw` and normalize to `merchant_normalized` | M1-B (DONE) | Survey (Miner 3) |
| 23 | Transaction Time Extraction | Date/time regex extraction, precision tagging, zero hallucination | M1-B (DONE) | Survey (Miner 3) |
| 24 | Order ID Extraction & Completeness | Extract platform ID, classify `COMPLETE`, `MASKED`, `TRUNCATED`, ellipsis/asterisk protection | M1-B (DONE) | Survey (Miner 3) |
| 25 | Field Evidence Collection | Record bounding boxes, confidence, text line for candidate fields | M1-B (DONE) | Survey (Miner 3) |
| 26 | Draft Assembly Pipeline | Synthesize candidate fields, issues, and duplicates into draft entity | M1-B (DONE) | Survey (Miner 3) |
| 27 | 3D Orthogonal Grouping | Orthogonal management of Categories, Projects, and Tags | M1-B (DONE) | Survey (Miner 3) |
| 28 | Classification Rule Hierarchy | 6-tier classification priority (Manual > Rules > History > Keywords > AI > Fallback) | M1-B (DONE) | Survey (Miner 3) |
| 29 | Pattern Matching (Wildcard/Regex) | SQL `%`, `_` wildcards and regular expression matching for rules | M1-B (DONE) | Survey (Miner 3) |
| 30 | Dynamic Rule Learning | Create merchant classification rule on user confirmation, monotonic microsecond IDs | M1-B (DONE) | Survey (Miner 3) |
| 31 | CSV Formula Injection Protection | Prepend single quote `'` for cells starting with `=`, `+`, `-`, `@`, `\t`, `\r` | M-Final (DONE) | Survey (Miner 3) |
| 32 | SWBK v1 Encrypted Backup | PBKDF2-HMAC-SHA256 (100k) + AES-256-GCM container format | M-Final (DONE) | Survey (Miner 3) |
| 33 | DDL & Cascade Verification Suite | Automated test suite verifying 12 tables, 11 indices, cascade triggers | M-Final (DONE) | Survey (Miner 2, 3) |
| 34 | Pigeon Codec Verification Suite | Unit test verifying Pigeon serialization, mock APIs, and error paths | M-Final (DONE) | Survey (Miner 1, 3) |
| 35 | Dedup & State Machine Test Suite | Unit tests verifying all 4 deduplication tiers and state transitions | M-Final (DONE) | Survey (Miner 2, 3) |
| 36 | OCR Parsing & Rule Engine Test Suite | Unit tests verifying parsing pipeline and 6-tier rule matching | M-Final (DONE) | Survey (Miner 3) |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Flutter Project Scaffold & Native Pigeon Bridge | F1-F6: Project setup, `pubspec.yaml`, Pigeon code generation, Android/iOS bridge adapters, coordinate normalization, static analysis | none | **DONE** (Gate Passed: 56/56 tests pass, flutter analyze clean, all reviews APPROVE, audit CLEAN) |
| M1-A | Unified SQLite Data Layer & Core Ledger Transactions | F7-F18: 12 tables DDL, 11 indices, foreign keys & cascade rules, integer cents math, 4-tier deduplication, transaction manager, state machine | M0 | **DONE** (Gate Passed: 145/145 tests pass, flutter analyze clean, all reviews APPROVE, audit CLEAN) |
| M1-B | OCR Transaction Parsing Pipeline & Classification Rule Engine | F19-F30: 8-stage parsing pipeline, noise filters, amount disambiguation, merchant normalization, order ID extraction, 6-tier classification rules | M0, M1-A | **DONE** (Gate Passed: 297/297 tests pass, flutter analyze clean, all reviews APPROVE, audit CLEAN) |
| M-Final | Acceptance Verification & Final Sign-Off | F31-F36: Full acceptance verification of R1, R2, R3, R4, exit code 0 on all gates, final completion reporting | M0, M1-A, M1-B | **DONE** (Gate Passed: 297/297 tests pass, flutter analyze clean, 6/6 docs suites pass, audit CLEAN) |

---

## Interface Contracts

### 1. Pigeon Native Bridge: HostApi ↔ FlutterApi
- **IDL File**: `pigeons/native_bridge.dart`
- **Host Interface**: `NativeCaptureHostApi`
- **Flutter Receiver Interface**: `NativeCaptureFlutterApi`

### 2. Database Helper ↔ Feature Repositories
- **Database Connection**: SQLite opened with `PRAGMA foreign_keys = ON;`
- **Currency Standard**: All monetary inputs and outputs must use `int amountMinor` (in cents). No floating point types (`double`) allowed for currency storage.

### 3. OCR Parsing Engine ↔ Drafts Feature
- **Pipeline Class**: `OcrParsingPipeline` in `lib/features/recognition/ocr_pipeline.dart`
- **Sub-parsers**: `NoiseFilter`, `AmountParser`, `MerchantNormalizer`, `OrderIdParser`, `ChannelStatusParser`.

### 4. Classification Rule Engine ↔ Ledger
- **Engine Class**: `ClassificationRuleEngine` in `lib/features/classification/rule_engine.dart`
- **Matcher Class**: `RuleMatcher` in `lib/features/classification/rule_matcher.dart`
- **Precedence Hierarchy (6 Tiers)**:
  1. Manual user override
  2. Active custom rule matches (`priority DESC`, regex & wildcard `%`, `_`)
  3. Historical transaction matching (same merchant -> most frequent category)
  4. Built-in keyword dictionary mapping
  5. AI recommendation (extensible hook / stub)
  6. Default fallback category (`cat_other` / Unclassified)
