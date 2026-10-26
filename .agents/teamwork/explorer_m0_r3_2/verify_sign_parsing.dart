// Standalone verification script for proposed CurrencyUtils sign parsing logic.

class ProposedCurrencyUtils {
  static int parseToMinorUnits(
    String input, {
    bool allowNegative = false,
    bool stripCurrencySymbols = true,
    bool roundSubUnits = false,
  }) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty currency string');
    }

    bool isNegative = false;
    bool hasLeadingSign = false;

    if (trimmed.startsWith('-')) {
      isNegative = true;
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      hasLeadingSign = true;
      trimmed = trimmed.substring(1).trim();
    }

    if (hasLeadingSign && (trimmed.startsWith('-') || trimmed.startsWith('+'))) {
      throw FormatException('Invalid currency string with multiple signs: "$input"');
    }

    if (stripCurrencySymbols) {
      trimmed = trimmed.replaceFirst(
        RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
        '',
      );
      if (hasLeadingSign) {
        if (trimmed.startsWith('-') || trimmed.startsWith('+')) {
          throw FormatException('Invalid currency string with multiple signs: "$input"');
        }
      } else {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        }
        if (hasLeadingSign && (trimmed.startsWith('-') || trimmed.startsWith('+'))) {
          throw FormatException('Invalid currency string with multiple signs: "$input"');
        }
      }
    }

    trimmed = trimmed.replaceAll(',', '').replaceAll(' ', '');

    if (trimmed.isEmpty || trimmed == '.') {
      throw FormatException('Invalid currency string: "$input"');
    }

    if (isNegative && !allowNegative) {
      throw const FormatException('Negative amount not allowed');
    }

    final parts = trimmed.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid currency format with multiple decimal points: "$input"');
    }

    final integerStr = parts[0];
    final int majorUnits;
    if (integerStr.isEmpty) {
      majorUnits = 0;
    } else {
      if (!RegExp(r'^\d+$').hasMatch(integerStr)) {
        throw FormatException('Invalid characters in currency integer part: "$input"');
      }
      final parsed = int.tryParse(integerStr);
      if (parsed == null) {
        throw FormatException('Currency integer part overflow: "$input"');
      }
      majorUnits = parsed;
    }

    int minorUnits = 0;
    if (parts.length == 2) {
      final decimalStr = parts[1];
      if (decimalStr.isNotEmpty) {
        if (!RegExp(r'^\d+$').hasMatch(decimalStr)) {
          throw FormatException('Invalid characters in currency decimal part: "$input"');
        }

        if (decimalStr.length == 1) {
          minorUnits = int.parse(decimalStr) * 10;
        } else if (decimalStr.length == 2) {
          minorUnits = int.parse(decimalStr);
        } else {
          final base = int.parse(decimalStr.substring(0, 2));
          if (roundSubUnits) {
            final nextDigit = int.parse(decimalStr[2]);
            minorUnits = nextDigit >= 5 ? base + 1 : base;
          } else {
            minorUnits = base;
          }
        }
      }
    }

    // Integer overflow protection (explorer_m0_r3_1 coordinate)
    const maxSafeMajor = 92233720368547758; // 9223372036854775807 ~/ 100
    if (majorUnits > maxSafeMajor || (majorUnits == maxSafeMajor && minorUnits > 7)) {
      throw FormatException('Currency amount exceeds 64-bit integer capacity: "$input"');
    }

    final total = majorUnits * 100 + minorUnits;
    return isNegative ? -total : total;
  }

  static int? tryParseToMinorUnits(
    String? input, {
    bool allowNegative = false,
    bool stripCurrencySymbols = true,
    bool roundSubUnits = false,
  }) {
    if (input == null) return null;
    try {
      return parseToMinorUnits(
        input,
        allowNegative: allowNegative,
        stripCurrencySymbols: stripCurrencySymbols,
        roundSubUnits: roundSubUnits,
      );
    } on FormatException {
      return null;
    }
  }
}

void main() {
  int passed = 0;
  int failed = 0;

  void testExpect(String desc, void Function() fn) {
    try {
      fn();
      passed++;
    } catch (e, st) {
      print('FAILED: $desc - $e\n$st');
      failed++;
    }
  }

  void testThrows(String desc, String input, {bool allowNegative = true}) {
    testExpect(desc, () {
      bool threw = false;
      try {
        ProposedCurrencyUtils.parseToMinorUnits(input, allowNegative: allowNegative);
      } on FormatException {
        threw = true;
      }
      if (!threw) {
        throw Exception('Expected FormatException for "$input", but it did not throw!');
      }
      final tryResult = ProposedCurrencyUtils.tryParseToMinorUnits(input, allowNegative: allowNegative);
      if (tryResult != null) {
        throw Exception('Expected tryParseToMinorUnits("$input") to be null, got $tryResult');
      }
    });
  }

  void testEquals(String desc, String input, int expected, {bool allowNegative = false, bool stripCurrencySymbols = true}) {
    testExpect(desc, () {
      final res = ProposedCurrencyUtils.parseToMinorUnits(
        input,
        allowNegative: allowNegative,
        stripCurrencySymbols: stripCurrencySymbols,
      );
      if (res != expected) {
        throw Exception('For "$input", expected $expected, got $res');
      }
      final tryRes = ProposedCurrencyUtils.tryParseToMinorUnits(
        input,
        allowNegative: allowNegative,
        stripCurrencySymbols: stripCurrencySymbols,
      );
      if (tryRes != expected) {
        throw Exception('For tryParseToMinorUnits("$input"), expected $expected, got $tryRes');
      }
    });
  }

  print('=== Running Malformed Conflicting Sign Test Cases ===');
  // Mandatory invalid patterns from orchestrator mission:
  // "+-10", "-+10", "++10", "--10", "+¥-10", "-¥+10", "-¥-10"
  testThrows('Pattern +-10', '+-10');
  testThrows('Pattern -+10', '-+10');
  testThrows('Pattern ++10', '++10');
  testThrows('Pattern --10', '--10');
  testThrows('Pattern +¥-10', '+¥-10');
  testThrows('Pattern -¥+10', '-¥+10');
  testThrows('Pattern -¥-10', '-¥-10');

  // Additional adversarial sign combinations
  testThrows('Pattern +¥+10', '+¥+10');
  testThrows('Pattern + ¥ - 10 (with spaces)', '+ ¥ - 10');
  testThrows('Pattern - ¥ + 10 (with spaces)', '- ¥ + 10');
  testThrows('Pattern + - 10 (with spaces)', '+ - 10');
  testThrows('Pattern - + 10 (with spaces)', '- + 10');
  testThrows('Pattern ++ 10 (with spaces)', '++ 10');
  testThrows('Pattern -- 10 (with spaces)', '-- 10');
  testThrows('Pattern ¥+-10', '¥+-10');
  testThrows('Pattern ¥-+10', '¥-+10');
  testThrows('Pattern ¥++10', '¥++10');
  testThrows('Pattern ¥--10', '¥--10');
  testThrows('Pattern ¥ + - 10', '¥ + - 10');
  testThrows('Pattern ¥ - - 10', '¥ - - 10');
  testThrows('Pattern +-¥10', '+-¥10');
  testThrows('Pattern -+¥10', '-+¥10');
  testThrows('Pattern ++¥10', '++¥10');
  testThrows('Pattern --¥10', '--¥10');
  testThrows('Pattern +CNY-10', '+CNY-10');
  testThrows('Pattern -CNY+10', '-CNY+10');
  testThrows('Pattern +CNY+10', '+CNY+10');
  testThrows('Pattern -CNY-10', '-CNY-10');
  testThrows('Pattern +-', '+-');
  testThrows('Pattern -+', '-+');
  testThrows('Pattern ++', '++');
  testThrows('Pattern --', '--');
  testThrows('Pattern +¥-', '+¥-');
  testThrows('Pattern -¥+', '-¥+');
  testThrows('Pattern -¥-', '-¥-');
  testThrows('Pattern +¥+', '+¥+');
  testThrows('Pattern +', '+');
  testThrows('Pattern -', '-');
  testThrows('Pattern +¥', '+¥');
  testThrows('Pattern -¥', '-¥');
  testThrows('Pattern ¥+', '¥+');
  testThrows('Pattern ¥-', '¥-');

  print('=== Running Valid Sign & Currency Combinations ===');
  testEquals('Standard positive 28.90', '28.90', 2890);
  testEquals('Explicit positive +28.90', '+28.90', 2890);
  testEquals('Explicit positive leading dot +.50', '+.50', 50);
  testEquals('Standard currency ¥28.90', '¥28.90', 2890);
  testEquals('Positive currency +¥28.90', '+¥28.90', 2890);
  testEquals('Currency positive ¥+28.90', '¥+28.90', 2890);
  testEquals('Fullwidth symbol ￥ 100.00', '￥ 100.00', 10000);
  testEquals('Currency code CNY 50.00', 'CNY 50.00', 5000);
  testEquals('Positive currency code +CNY 50.00', '+CNY 50.00', 5000);
  testEquals('Currency code positive CNY +50.00', 'CNY +50.00', 5000);

  testEquals('Standard negative -28.90', '-28.90', -2890, allowNegative: true);
  testEquals('Negative leading dot -.50', '-.50', -50, allowNegative: true);
  testEquals('Negative symbol before -¥28.90', '-¥28.90', -2890, allowNegative: true);
  testEquals('Negative symbol after ¥-28.90', '¥-28.90', -2890, allowNegative: true);
  testEquals('Negative CNY before -CNY 50.00', '-CNY 50.00', -5000, allowNegative: true);
  testEquals('Negative CNY after CNY -50.00', 'CNY -50.00', -5000, allowNegative: true);

  testThrows('Negative disallowed -28.90', '-28.90', allowNegative: false);
  testThrows('Negative disallowed -¥28.90', '-¥28.90', allowNegative: false);
  testThrows('Negative disallowed ¥-28.90', '¥-28.90', allowNegative: false);

  print('=== Results: Passed: $passed, Failed: $failed ===');
  if (failed > 0) {
    throw Exception('$failed tests failed!');
  }
}
