// lib/features/classification/rule_matcher.dart
import '../../data/models/classification_rule.dart';

/// High-performance pattern compiler and rule matcher for classification rules
class RuleMatcher {
  RuleMatcher._();

  static const int maxPatternLength = 200;

  /// Compiles SQL wildcard pattern (% and _) or regex into a safe RegExp
  static RegExp patternToRegExp(String pattern, {bool caseSensitive = false}) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      return RegExp(r'^$', caseSensitive: caseSensitive);
    }

    if (trimmed.length > maxPatternLength) {
      throw ArgumentError('Merchant pattern exceeds maximum length of $maxPatternLength characters.');
    }

    // 1. Explicit regex with prefix "regex:"
    if (trimmed.startsWith('regex:')) {
      final raw = trimmed.substring(6).trim();
      return RegExp(raw, caseSensitive: caseSensitive);
    }

    // 2. Anchored regular expression (^...$)
    if (trimmed.startsWith('^') && trimmed.endsWith(r'$')) {
      return RegExp(trimmed, caseSensitive: caseSensitive);
    }

    // 3. SQL Wildcard pattern (% or _)
    final hasWildcard = trimmed.contains('%') || trimmed.contains('_');
    if (hasWildcard) {
      // Collapse redundant %%% -> % to prevent ReDoS
      final collapsed = trimmed.replaceAll(RegExp(r'%+'), '%');
      final buffer = StringBuffer('^');
      for (int i = 0; i < collapsed.length; i++) {
        final char = collapsed[i];
        if (char == '%') {
          buffer.write('.*');
        } else if (char == '_') {
          buffer.write('.');
        } else {
          buffer.write(RegExp.escape(char));
        }
      }
      buffer.write(r'$');
      return RegExp(buffer.toString(), caseSensitive: caseSensitive);
    }

    // 4. Plain text: substring contains matching
    return RegExp(RegExp.escape(trimmed), caseSensitive: caseSensitive);
  }

  /// Tests if a [pattern] matches a [target] string
  static bool matches({
    required String pattern,
    required String target,
  }) {
    final candidateTarget = target.trim();
    if (candidateTarget.isEmpty && pattern.trim().isNotEmpty) return false;

    try {
      final regex = patternToRegExp(pattern);
      return regex.hasMatch(candidateTarget);
    } catch (_) {
      // Malformed pattern fails safely
      return false;
    }
  }

  /// Evaluates a ClassificationRule against candidate transaction attributes
  static bool evaluateRule({
    required ClassificationRule rule,
    required String merchantRaw,
    String? merchantNormalized,
    String? paymentChannel,
  }) {
    if (rule.enabled != 1) return false;

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

    return false;
  }

  /// Deterministic tie-breaking comparator for classification rules
  /// 1. Priority DESC
  /// 2. Pattern specificity (length) DESC
  /// 3. Created date DESC
  static int compareRules(ClassificationRule a, ClassificationRule b) {
    if (a.priority != b.priority) {
      return b.priority.compareTo(a.priority);
    }
    if (a.merchantPattern.length != b.merchantPattern.length) {
      return b.merchantPattern.length.compareTo(a.merchantPattern.length);
    }
    return b.createdAt.compareTo(a.createdAt);
  }
}
