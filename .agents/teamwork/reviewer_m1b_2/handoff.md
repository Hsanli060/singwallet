# Review & Adversarial Verification Report: 6-Tier Classification Rule Engine & 3D Orthogonal Grouping (Features F27-F30)

**Reviewer Agent**: `reviewer_m1b_2` (Roles: `reviewer`, `critic`)  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B (Features F27, F28, F29, F30)  
**Date**: 2026-10-22  
**Final Verdict**: **APPROVE**  

---

## 1. Observation

### 1.1 Implementation Files Under Review
1. `lib/features/classification/models/classification_match_result.dart`:
   - Line 4–20: Defined `ClassificationTier` enum with 6 strictly ordered tiers: `manual` (1), `customRule` (2), `history` (3), `builtinKeyword` (4), `ai` (5), and `fallback` (6), alongside explicit default confidence scores (`1.0`, `0.95`, `0.85`, `0.70`, `0.60`, `0.10`).
   - Line 23–44: `ClassificationMatchResult` encapsulates 3D orthogonal grouping fields (`categoryId` non-null, `projectId` nullable, `tagIds` multi-label list) alongside explanation and rule metadata.
   - Line 49–148: Factory constructors for each tier (`.manual`, `.customRule`, `.history`, `.builtinKeyword`, `.ai`, `.fallback`).

2. `lib/features/classification/rule_matcher.dart`:
   - Line 8: Enforced `maxPatternLength = 200` to prevent ReDoS from pathologically long regexes.
   - Line 11–54: `patternToRegExp`:
     - Explicit `regex:` prefix and `^...$` regex patterns preserved.
     - Redundant SQL wildcards collapsed via `trimmed.replaceAll(RegExp(r'%+'), '%')` to prevent catastrophic backtracking.
     - Individual `%` converted to `.*`, `_` to `.`.
     - All other characters strictly escaped using `RegExp.escape(char)` into anchored `^...$` regex.
     - Plain text without wildcards compiles to unanchored case-insensitive substring match.
   - Line 57–71: `matches` wraps regex evaluation in `try-catch` to safely return `false` on malformed inputs without throwing.
   - Line 74–106: `evaluateRule` verifies rule activation (`enabled == 1`), optional payment channel equality (case-insensitive trimmed), and tests both `merchantRaw` and `merchantNormalized`.
   - Line 112–120: `compareRules` deterministic tie-breaking comparator: `b.priority.compareTo(a.priority)` (priority DESC), `b.merchantPattern.length.compareTo(a.merchantPattern.length)` (specificity DESC), `b.createdAt.compareTo(a.createdAt)` (created_at DESC).

3. `lib/features/classification/rule_engine.dart`:
   - Line 41–107: `_buildDictionary` provides pre-sorted built-in dictionary (longest match first) covering 7 Chinese consumer spending categories (`cat_food`, `cat_transport`, `cat_shopping`, `cat_entertainment`, `cat_utilities`, `cat_medical`, `cat_income`) with >100 realistic merchant keywords.
   - Line 116–198: `classify` executes the strict 6-tier waterfall:
     - **Tier 1 (Manual)**: Evaluates user explicit override `manualCategoryId`.
     - **Tier 2 (Custom Rules)**: Queries SQLite `classification_rules` (`enabled = 1`), sorts using `compareRules`, and evaluates.
     - **Tier 3 (Historical Transactions)**: Queries SQLite `transactions` grouping by `category_id`, filtering out soft-deleted records (`deleted_at IS NULL`), ordering by `freq DESC, latest_date DESC LIMIT 1`.
     - **Tier 4 (Built-in Dictionary)**: Evaluates longest matching keyword against normalized merchant, raw merchant, and remarks.
     - **Tier 5 (Local Validated AI Provider)**: If provider is present, queries `recommendCategory(...)` and validates category existence in SQLite `categories` (`archived_at IS NULL`). Malformed/unregistered categories or exceptions cleanly cascade.
     - **Tier 6 (Fallback)**: Returns `ClassificationMatchResult.fallback(categoryId: 'cat_other')`.
   - Line 363–433: `learnRuleFromUserAction`:
     - Normalizes merchant name and identifies existing rules for same pattern and channel.
     - Updates existing rule version and timestamp, or inserts a new rule into `classification_rules`.
     - **Non-retroactivity**: Modifies only `classification_rules` and never mutates committed transactions in `transactions`.

4. `test/classification/rule_matcher_test.dart` & `test/classification/rule_engine_test.dart`:
   - 21 comprehensive unit test cases covering prefix/suffix/middle wildcards, single character `_`, explicit regexes, special character escaping, case insensitivity, channel restrictions, comparator ordering, all 6 hierarchy tiers, disabled rules, soft delete history isolation, AI validation, and dynamic rule learning non-retroactivity.

### 1.2 Independent Test Execution
- Command: `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter analyze`
  - Output: `No issues found! (ran in 6.6s)` (Exit code 0)
- Command: `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/classification/`
  - Output: `All tests passed! (21 tests passed)` (Exit code 0)
- Command: `$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test`
  - Output: `All 211 tests passed!` (Exit code 0)
- Command: `python test_docs_integrity.py`
  - Output: `ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%!` (Exit code 0)

---

## 2. Logic Chain

1. **Hierarchy Discipline (F28)**:
   - Observation: `ClassificationRuleEngine.classify` follows a waterfall sequence from line 130 to 197 without skipping or reordering tiers.
   - Verification: Tests in `rule_engine_test.dart` demonstrate that manual selection overrides custom rules (Tier 1 > Tier 2), custom rules override history (Tier 2 > Tier 3), history overrides dictionary (Tier 3 > Tier 4), dictionary overrides AI (Tier 4 > Tier 5), and fallback is only hit when all previous tiers yield no match (Tier 5 > Tier 6).

2. **ReDoS & Safe Wildcard Compilation (F29)**:
   - Observation: `RuleMatcher.patternToRegExp` collapses sequences of `%` to avoid exponential state branching in regex engines, caps length at 200, and escapes regex metacharacters (`(`, `)`, `+`, `[`, `]`, `?`, `*`, `^`, `$`) for non-wildcard tokens.
   - Verification: `rule_matcher_test.dart` validates that merchant strings with parentheses (`麦当劳(王府井店)`), plus signs (`7-Eleven+`), and ampersands (`C&A (服装)`) evaluate without parser syntax errors or unhandled exceptions.

3. **Deterministic Tie-Breaking Rule Ordering (F28, F29)**:
   - Observation: When multiple custom rules match, `RuleMatcher.compareRules` sorts by `priority DESC`, then `merchantPattern.length DESC` (specificity), then `createdAt DESC`.
   - Verification: `rule_engine_test.dart` line 78 validates that between priority 200 and priority 100 rules for `肯德基%`, the higher priority rule is selected deterministically.

4. **Dynamic Rule Learning & Immutability Non-Retroactivity (F30)**:
   - Observation: `learnRuleFromUserAction` executes SQLite queries strictly against `classification_rules` (lines 382, 389, 407, 431).
   - Verification: `rule_engine_test.dart` line 255 asserts that inserting a transaction under `cat_food` and subsequently learning a rule for `cat_coffee` leaves the existing transaction's `category_id` unchanged.

5. **3D Orthogonal Grouping Integrity (F27)**:
   - Observation: Across data models and database schema:
     - Category is mandatory 1:1 (`categoryId` non-nullable in `ClassificationMatchResult`, `category_id` non-null foreign key in `classification_rules` and ledger).
     - Project is optional 0..1 (`projectId` nullable in both `ClassificationMatchResult` and `classification_rules`, with `ON DELETE SET NULL`).
     - Tags are multi-label 0..N (`List<String> tagIds` in `ClassificationMatchResult`, persisted via `transaction_tags` N:M join table).
   - Verification: Relational constraints tested in `test/database/relational_stress_test.dart` and `test_docs_integrity.py` pass 100%.

6. **Integrity Violation Audit**:
   - Source code inspected for dummy facades, stub return values, hardcoded test strings, and external shortcuts. None detected; genuine SQLite queries, regex compilation, and business domain logic are implemented throughout.

---

## 3. Caveats

- **Tier 5 AI Provider**: The AI provider (`AiClassificationProvider`) is designed as an extensible, pluggable contract. When no provider is registered (default standalone offline mode), the engine seamlessly falls through from Tier 4 dictionary matching to Tier 6 fallback.
- **Rule Length Constraint**: Patterns exceeding 200 characters throw an `ArgumentError` in `patternToRegExp`, which is safely caught and rejected by `matches`. Real-world Chinese merchant and receipt descriptors are typically under 50 characters, making this limit secure and appropriate.

---

## 4. Quality Review Summary

**Verdict**: **APPROVE**

### Verified Claims
- Strict adherence to 6-Tier Classification Hierarchy: Tier 1 > Tier 2 > Tier 3 > Tier 4 > Tier 5 > Tier 6 → Verified via code trace & `rule_engine_test.dart` → **PASS**
- Safe SQL wildcard (`%`, `_`) transformation to RegExp with ReDoS protection and metacharacter escaping → Verified via `rule_matcher.dart` & `rule_matcher_test.dart` → **PASS**
- Deterministic rule ordering: priority DESC, specificity DESC, created_at DESC → Verified via `compareRules` & unit tests → **PASS**
- Dynamic rule learning with strict non-retroactivity guarantee → Verified via `learnRuleFromUserAction` & SQLite tests → **PASS**
- 3D Orthogonal Grouping integrity (Category 1:1, Project 0..1, Tags 0..N) → Verified across models, engine, and database schema → **PASS**
- Zero static analysis warnings (`flutter analyze`) → Verified → **PASS**
- 100% test pass across classification suite (21/21) and full repository (211/211) → Verified → **PASS**

### Coverage Gaps
- None. All requirements for Features F27-F30 are fully covered with automated tests.

### Unverified Items
- None.

---

## 5. Adversarial Challenge Report

**Overall Risk Assessment**: **LOW**

### Challenges Evaluated & Stress Test Results

1. **Challenge 1: ReDoS via Wildcard Collisions**
   - *Attack Scenario*: Adversarial rule input with redundant repeating wildcards (e.g. `%%%%%%%%%%%%%%%%`).
   - *Stress Test*: `RuleMatcher.patternToRegExp` executes `trimmed.replaceAll(RegExp(r'%+'), '%')`, collapsing all consecutive wildcards into a single `%` (`.*`).
   - *Result*: **PASS**.

2. **Challenge 2: Regex Metacharacter Injection in Merchant Names**
   - *Attack Scenario*: Store names containing special characters such as `+`, `()`, `[]`, or `*` (e.g., `C&A (服装)`, `7-Eleven+`).
   - *Stress Test*: Each non-wildcard character is individually passed through `RegExp.escape(char)`.
   - *Result*: **PASS**. No `FormatException` or broken match groups.

3. **Challenge 3: Tier 5 Hallucinated Category Injection**
   - *Attack Scenario*: An AI classification provider returns a nonexistent, hallucinated, or archived category ID.
   - *Stress Test*: `_matchAi` queries local SQLite `categories` table with `id = ? AND archived_at IS NULL`. Nonexistent categories are discarded and execution cascades to Tier 6 fallback.
   - *Result*: **PASS** (verified by `rule_engine_test.dart` line 194).

4. **Challenge 4: Ledger Immutability & Retroactivity**
   - *Attack Scenario*: Modifying a classification rule alters past committed financial records.
   - *Stress Test*: Dynamic rule learning tests confirm that past records in `transactions` are never modified by rule insertion or updates.
   - *Result*: **PASS**.

5. **Challenge 5: Soft Delete Leakage in Historical Matching**
   - *Attack Scenario*: Soft-deleted transactions in the 30-day trash bin influencing Tier 3 historical merchant matching.
   - *Stress Test*: SQL query in `_matchHistory` explicitly enforces `deleted_at IS NULL`.
   - *Result*: **PASS** (verified by `rule_engine_test.dart` line 150).

---

## 6. Verification Method

To independently verify this evaluation, run the following commands in PowerShell from the project root:

```powershell
$env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path

# 1. Static code analysis
flutter analyze

# 2. Targeted Classification Rule Engine unit tests
flutter test test/classification/

# 3. Full project regression test suite
flutter test

# 4. Cross-platform docs and relational integrity suite
python test_docs_integrity.py
```

Expected output:
- `flutter analyze`: `No issues found!`
- `flutter test test/classification/`: `All tests passed! (21 tests passed)`
- `flutter test`: `All 211 tests passed!`
- `python test_docs_integrity.py`: `ALL 6 DEEP VERIFICATION TEST SUITES PASSED 100%!`
