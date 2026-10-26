# Detailed Fix Strategy: Classification & Rule Engine Defects

**Explorer Subagent**: `explorer_m1b_r2_2`  
**Parent Orchestrator**: `a14d1a00-adfd-46db-a470-136d68156a40`  
**Milestone**: M1-B Remediation (Features F27–F30)  
**Date**: 2026-10-22  

---

## Executive Summary

Following the M1-B forensic audit (`auditor_m1b_1/handoff.md`) and empirical adversarial investigation (`challenger_m1b_2/handoff.md`), this document formulates the production-ready fix strategy for all defects in `RuleMatcher` and `ClassificationRuleEngine`.

The strategy addresses 5 concrete issues across 2 core modules:
1. **RuleMatcher**:
   - **Defect 1.1**: Rejection of empty target strings against pure `%` wildcard patterns.
   - **Defect 1.2**: Isolate CPU lockup (>45s) from catastrophic ReDoS backtracking on nested quantifiers in `regex:` patterns.
   - **Defect 1.3**: Shadowing of channel-specific rules by newer global rules due to missing channel specificity in the tie-breaking comparator.
2. **ClassificationRuleEngine**:
   - **Defect 2.1**: SQLite 1555 `UNIQUE constraint failed: classification_rules.id` crash when learning rules rapidly in the same millisecond.
   - **Defect 2.2**: Brand/sub-brand normalization disparity causing learned rules to be skipped and overshadowed by historical transactions or dictionary fallback.

---

## Part 1: RuleMatcher Remediation Strategy

### Defect 1.1: Pure Wildcard Patterns (`%%%%%`) Matching Empty Strings

#### 1. Root Cause Analysis
- **File**: `lib/features/classification/rule_matcher.dart`, lines 61–63:
  ```dart
  final candidateTarget = target.trim();
  if (candidateTarget.isEmpty && pattern.trim().isNotEmpty) return false;
  ```
- **Mechanism**: The guard unconditionally rejects any empty target string whenever `pattern.trim()` is not empty. However, under SQL semantics, `%` matches zero or more arbitrary characters. A pattern composed entirely of `%` wildcards (e.g. `%`, `%%`, `%%%%%`) mathematically matches an empty string `""`.
- **Impact**: In adversarial test 1.1, `RuleMatcher.matches(pattern: '%%%%%', target: '')` returned `false` instead of `true`.

#### 2. Exact Remediation
In `lib/features/classification/rule_matcher.dart`, replace the unconditional rejection with a wildcard check and regex-aware evaluation:

```dart
// lib/features/classification/rule_matcher.dart
  static bool matches({
    required String pattern,
    required String target,
  }) {
    final candidateTarget = target.trim();
    final candidatePattern = pattern.trim();

    if (candidateTarget.isEmpty) {
      if (candidatePattern.isEmpty) return true;
      // SQL % matches zero or more characters. A pattern consisting solely of % matches empty string.
      if (candidatePattern.split('').every((c) => c == '%')) {
        return true;
      }
      // Check explicit regex patterns that may genuinely match an empty string (e.g., ^$, .*, a*)
      if (candidatePattern.startsWith('regex:') ||
          (candidatePattern.startsWith('^') && candidatePattern.endsWith(r'$'))) {
        try {
          final regex = patternToRegExp(candidatePattern);
          return regex.hasMatch(candidateTarget);
        } catch (_) {
          return false;
        }
      }
      return false;
    }

    try {
      final regex = patternToRegExp(pattern);
      return regex.hasMatch(candidateTarget);
    } catch (_) {
      // Malformed pattern fails safely
      return false;
    }
  }
```

---

### Defect 1.2: ReDoS Vulnerability on Nested Quantifiers in `regex:` Patterns

#### 1. Root Cause Analysis
- **File**: `lib/features/classification/rule_matcher.dart`, lines 21–25:
  ```dart
  if (trimmed.startsWith('regex:')) {
    final raw = trimmed.substring(6).trim();
    return RegExp(raw, caseSensitive: caseSensitive);
  }
  ```
- **Mechanism**: Dart compiles regular expressions using Google V8's Irregexp engine. When a pattern contains nested quantifiers, such as `^(a+)+$`, `(a*)*`, or `(a|b+)+`, evaluating it against a non-matching string of repeating characters triggers $O(2^n)$ backtracking states.
- **Empirical Measurement**: Evaluating `regex:^(a+)+$` against `'a' * 33 + '!'` blocked the Dart event loop isolate for **45.9 seconds**, exceeding the 30-second CI timeout and creating an Application Not Responding (ANR) lockup in Flutter.

#### 2. Exact Remediation
Implement compile-time static safety validation in `RuleMatcher`:
1. Reject dangerous consecutive quantifiers (`++`, `**`, `+*`, `*+`).
2. Detect nested quantifiers (a quantified group containing quantifiers or followed by quantifiers), including deeply nested variations.
3. Throw an `ArgumentError` when a pattern is flagged. Because `matches()` wraps `patternToRegExp` in a `try ... catch (_)`, malicious or pathological patterns will immediately return `false` within microseconds rather than freezing the isolate.

```dart
// In lib/features/classification/rule_matcher.dart

  static final RegExp _nestedQuantifiersPattern = RegExp(
    r'\((?:[^()\\]|\\.)*(?:[*+]|\{\d+,?\d*\})(?:[^()\\]|\\.)*\)\s*(?:[*+]|\{\d+,?\d*\})',
  );

  static final RegExp _consecutiveQuantifiersPattern = RegExp(
    r'[*+]{2,}',
  );

  /// Validates regex patterns to prevent ReDoS catastrophic backtracking
  static void validateRegexSafety(String rawRegex) {
    if (_consecutiveQuantifiersPattern.hasMatch(rawRegex)) {
      throw ArgumentError(
        'Dangerous consecutive quantifiers detected: $rawRegex',
      );
    }

    // Simplify harmless inner groups without quantifiers to catch deeply nested ReDoS patterns
    var simplified = rawRegex;
    final harmlessGroup = RegExp(r'\(([^()*+?{}\\]|\\.)*\)');
    for (int i = 0; i < 5; i++) {
      if (!harmlessGroup.hasMatch(simplified)) break;
      simplified = simplified.replaceAll(harmlessGroup, 'x');
    }

    if (_nestedQuantifiersPattern.hasMatch(simplified)) {
      throw ArgumentError(
        'Potentially catastrophic ReDoS pattern detected: nested quantifiers are not permitted ($rawRegex).',
      );
    }
  }
```

In `patternToRegExp`:
```dart
    // 1. Explicit regex with prefix "regex:"
    if (trimmed.startsWith('regex:')) {
      final raw = trimmed.substring(6).trim();
      validateRegexSafety(raw);
      return RegExp(raw, caseSensitive: caseSensitive);
    }

    // 2. Anchored regular expression (^...$)
    if (trimmed.startsWith('^') && trimmed.endsWith(r'$')) {
      validateRegexSafety(trimmed);
      return RegExp(trimmed, caseSensitive: caseSensitive);
    }
```

---

### Defect 1.3: Tie-Breaking Comparator Missing Channel Specificity

#### 1. Root Cause Analysis
- **File**: `lib/features/classification/rule_matcher.dart`, lines 112–120:
  ```dart
  static int compareRules(ClassificationRule a, ClassificationRule b) {
    if (a.priority != b.priority) {
      return b.priority.compareTo(a.priority);
    }
    if (a.merchantPattern.length != b.merchantPattern.length) {
      return b.merchantPattern.length.compareTo(a.merchantPattern.length);
    }
    return b.createdAt.compareTo(a.createdAt);
  }
  ```
- **Mechanism**: The comparator evaluates `priority DESC`, `pattern.length DESC`, and then directly falls back to `createdAt DESC`. It completely ignores channel specificity (`paymentChannel != null` vs `paymentChannel == null`).
- **Consequence**: If a user creates a channel-specific rule (`全家` + `wechat` -> `cat_food`, priority 100) and subsequently creates a global rule (`全家` + `null` -> `cat_shopping`, priority 100), the global rule has a higher `createdAt` timestamp. It sorts first and matches all WeChat transactions, **completely shadowing and muting the channel-specific rule**.

#### 2. Exact Remediation
Prioritize channel specificity immediately after pattern length and before `createdAt`:

```dart
// lib/features/classification/rule_matcher.dart
  /// Deterministic tie-breaking comparator for classification rules:
  /// 1. Priority DESC
  /// 2. Pattern specificity (length) DESC
  /// 3. Channel specificity (specific channel before global null channel)
  /// 4. Created date DESC
  static int compareRules(ClassificationRule a, ClassificationRule b) {
    if (a.priority != b.priority) {
      return b.priority.compareTo(a.priority);
    }
    if (a.merchantPattern.length != b.merchantPattern.length) {
      return b.merchantPattern.length.compareTo(a.merchantPattern.length);
    }
    final aHasChannel = a.paymentChannel != null && a.paymentChannel!.trim().isNotEmpty;
    final bHasChannel = b.paymentChannel != null && b.paymentChannel!.trim().isNotEmpty;
    if (aHasChannel != bHasChannel) {
      return (bHasChannel ? 1 : 0).compareTo(aHasChannel ? 1 : 0);
    }
    return b.createdAt.compareTo(a.createdAt);
  }
```

---

## Part 2: ClassificationRuleEngine Remediation Strategy

### Defect 2.1: Primary Key ID Collision in `learnRuleFromUserAction`

#### 1. Root Cause Analysis
- **File**: `lib/features/classification/rule_engine.dart`, line 417:
  ```dart
  final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}_${pattern.hashCode.abs()}';
  ```
- **Mechanism**: `millisecondsSinceEpoch` only has millisecond granularity. When two rules for the same merchant pattern are learned in rapid succession (e.g. generating channel rules for WeChat and Alipay back-to-back, or concurrent user confirmations), both `millisecondsSinceEpoch` and `pattern.hashCode.abs()` are identical.
- **SQLite Error**:
  ```text
  SqfliteFfiException(sqlite_error: 1555): UNIQUE constraint failed: classification_rules.id
  ```

#### 2. Exact Remediation
Incorporate a monotonic counter and microsecond timestamp into `ClassificationRuleEngine`:

```dart
// lib/features/classification/rule_engine.dart

class ClassificationRuleEngine {
  final DatabaseExecutor _db;
  final AiClassificationProvider? _aiProvider;
  final List<_DictionaryEntry> _dictionaryEntries;
  static int _ruleCounter = 0;
```

In `learnRuleFromUserAction`:
```dart
    // Insert new rule with microsecond precision and monotonic sequence
    final ruleId = 'rule_${DateTime.now().microsecondsSinceEpoch}_${_ruleCounter++}_${pattern.hashCode.abs()}';
    final newRule = ClassificationRule(
      id: ruleId,
      priority: priority,
      merchantPattern: pattern,
      paymentChannel: paymentChannel,
      categoryId: categoryId,
      projectId: projectId,
      enabled: 1,
      version: 1,
      createdAt: nowIso,
      updatedAt: nowIso,
    );

    await _db.insert('classification_rules', newRule.toMap());
    return newRule;
```

---

### Defect 2.2: Dynamic Rule Learning Pattern Cross-Mapping Across Raw/Normalized Merchants

#### 1. Root Cause Analysis
- **Files**:
  - `lib/features/recognition/merchant_normalizer.dart`: `_knownBrands` contains both compound brands (`'海底捞火锅'`, `'星巴克咖啡'`, `'瑞幸咖啡'`, `'奈雪的茶'`) and root brands (`'海底捞'`, `'星巴克'`, `'瑞幸'`, `'奈雪'`).
  - `lib/features/classification/rule_matcher.dart`: `RuleMatcher.evaluateRule` only checked if the incoming text contained the rule pattern.
- **Failure Mode**:
  1. User confirms a category on transaction `'海底捞火锅'`. `learnRuleFromUserAction` normalizes it to pattern `'海底捞火锅'`.
  2. Next transaction arrives as `'海底捞三里屯店'`. `MerchantNormalizer` normalizes it to root brand `'海底捞'`.
  3. During classification:
     - `matches(pattern: '海底捞火锅', target: '海底捞三里屯店')` is `false`.
     - `matches(pattern: '海底捞火锅', target: '海底捞')` is `false`.
  4. Tier 2 custom rules fail to match.
  5. The engine falls back to Tier 3 history or Tier 4 dictionary, incorrectly **overshadowing** the newly learned rule with historical categories.
- **Constraint Consideration**: `test/recognition/merchant_normalizer_test.dart` explicitly asserts that `'海底捞火锅'` normalizes to `'海底捞火锅'`. Modifying `MerchantNormalizer` would break recognition contracts. Therefore, the fix must reside in `RuleMatcher.evaluateRule` and `ClassificationRuleEngine`.

#### 2. Exact Remediation
1. **In `RuleMatcher.evaluateRule`**:
   Add bidirectional substring matching for plain-text merchant rules (rules without wildcards or regex):
   When `rule.merchantPattern` is plain text, check if `rule.merchantPattern` contains `targetNorm` OR `targetNorm` contains `rule.merchantPattern` (both length $\ge 2$).
   - E.g., rule `'海底捞火锅'` contains incoming target `'海底捞'` -> **MATCH**.
   - E.g., rule `'星巴克咖啡'` contains incoming target `'星巴克'` -> **MATCH**.
   - E.g., rule `'全家'` is contained within incoming target `'全家便利超市'` -> **MATCH**.

```dart
// In lib/features/classification/rule_matcher.dart -> evaluateRule()

    // 1. Channel check
    if (rule.paymentChannel != null && rule.paymentChannel!.trim().isNotEmpty) {
      final ruleChannel = rule.paymentChannel!.toLowerCase().trim();
      final ctxChannel = paymentChannel?.toLowerCase().trim();
      if (ruleChannel != ctxChannel) {
        return false;
      }
    }

    // 2. Pattern matching against raw and normalized merchant
    final targetRaw = merchantRaw.trim();
    final targetNorm = merchantNormalized?.trim() ?? '';

    if (matches(pattern: rule.merchantPattern, target: targetRaw)) {
      return true;
    }

    if (targetNorm.isNotEmpty && targetNorm != targetRaw) {
      if (matches(pattern: rule.merchantPattern, target: targetNorm)) {
        return true;
      }
    }

    // 3. Dynamic rule learning cross-matching:
    // If rule pattern is a plain text brand/sub-brand (no regex or SQL wildcards),
    // perform bidirectional containment matching with targetNorm (both length >= 2).
    final pat = rule.merchantPattern.trim();
    final isPlain = !pat.startsWith('regex:') &&
        !pat.contains('%') &&
        !pat.contains('_') &&
        !(pat.startsWith('^') && pat.endsWith(r'$'));
    if (isPlain && targetNorm.length >= 2 && pat.length >= 2) {
      final pLower = pat.toLowerCase();
      final nLower = targetNorm.toLowerCase();
      if (pLower.contains(nLower) || nLower.contains(pLower)) {
        return true;
      }
    }

    return false;
```

2. **In `ClassificationRuleEngine.learnRuleFromUserAction`**:
   Ensure existing rule lookups check both `pattern` and `merchantRaw.trim()` to avoid creating fragmented duplicate rules for the same merchant:

```dart
    final List<Map<String, dynamic>> existing;
    if (paymentChannel != null) {
      existing = await _db.query(
        'classification_rules',
        where: '(merchant_pattern = ? OR merchant_pattern = ?) AND payment_channel = ?',
        whereArgs: [pattern, merchantRaw.trim(), paymentChannel],
        limit: 1,
      );
    } else {
      existing = await _db.query(
        'classification_rules',
        where: '(merchant_pattern = ? OR merchant_pattern = ?) AND payment_channel IS NULL',
        whereArgs: [pattern, merchantRaw.trim()],
        limit: 1,
      );
    }
```

---

## Part 3: Test Suite Updates

To reflect the repaired behavior, update `test/classification/rule_engine_adversarial_test.dart`:

1. **Test 1.1**:
   Change:
   ```dart
   expect(RuleMatcher.matches(pattern: '%%%%%', target: ''), isFalse);
   ```
   To:
   ```dart
   expect(RuleMatcher.matches(pattern: '%%%%%', target: ''), isTrue);
   ```

2. **Test 1.5**:
   Update to assert safe rejection and execution speed (<10ms):
   ```dart
   test('1.5 Complex backtracking regexes with regex: prefix fail safely without ReDoS lockup', () {
     const redosPattern = r'regex:^(a+)+$';
     expect(
       () => RuleMatcher.patternToRegExp(redosPattern),
       throwsA(isA<ArgumentError>().having(
         (e) => e.message,
         'message',
         contains('ReDoS'),
       )),
     );

     final sw = Stopwatch()..start();
     final res = RuleMatcher.matches(pattern: redosPattern, target: '${'a' * 30}!');
     sw.stop();

     expect(res, isFalse);
     expect(sw.elapsedMilliseconds, lessThan(50));
   });
   ```

3. **Test 4.4**:
   Update to verify that rapid same-millisecond calls to `learnRuleFromUserAction` no longer collide:
   ```dart
   test('4.4 Rapid same-millisecond rule learning produces unique IDs without primary key collision', () async {
     const pattern = '同城便利店';
     final r1 = await engine.learnRuleFromUserAction(
       merchantRaw: pattern,
       categoryId: 'cat_food',
       paymentChannel: 'wechat',
     );
     final r2 = await engine.learnRuleFromUserAction(
       merchantRaw: pattern,
       categoryId: 'cat_shopping',
       paymentChannel: 'alipay',
     );

     expect(r1.id, isNot(equals(r2.id)));
     final rules = await db.query(
       'classification_rules',
       where: 'merchant_pattern = ?',
       whereArgs: [pattern],
     );
     expect(rules.length, 2);
   });
   ```

4. **Test 4.6**:
   Update the assertion in Test 4.6: channel-specific rule now wins over global rule:
   ```dart
   test('4.6 Channel-specific rule takes precedence over global rule when priorities are equal', () async {
     await engine.learnRuleFromUserAction(
       merchantRaw: '全家便利店',
       categoryId: 'cat_food',
       paymentChannel: 'wechat',
       priority: 100,
     );

     await engine.learnRuleFromUserAction(
       merchantRaw: '全家便利店',
       categoryId: 'cat_shopping',
       paymentChannel: null,
       priority: 100,
     );

     final res = await engine.classify(
       merchantRaw: '全家便利店',
       paymentChannel: 'wechat',
     );
     expect(res.categoryId, 'cat_food'); // Channel-specific rule prioritized!
   });
   ```

---

## Part 4: Verification Method

The worker implementer can verify these fixes via:

1. **Classification Tests Execution**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter test test/classification/
   ```
   *Expected*: All 52+ tests pass cleanly without timeout or error.

2. **Static Analysis**:
   ```powershell
   $env:Path = "C:\Other\Dev\flutter\bin;" + $env:Path; flutter analyze lib/features/classification/ test/classification/
   ```
   *Expected*: `No issues found!`.
