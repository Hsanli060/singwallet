// Verification of Option 1 vs Option 2 against explorer_m0_r3_3 test cases

class Option1CurrencyUtils {
  static const int _maxSafeMajor = 92233720368547758;
  static const int _maxMinorForBoundary = 7;

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

    if (stripCurrencySymbols) {
      trimmed = trimmed.replaceFirst(
        RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
        '',
      );
      if (!hasLeadingSign) {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasLeadingSign = true;
          trimmed = trimmed.substring(1).trim();
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

    if (majorUnits > _maxSafeMajor ||
        (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
      throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
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

class Option2CurrencyUtils {
  static const int _maxSafeMajor = 92233720368547758;
  static const int _maxMinorForBoundary = 7;

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

    // Fast-fail: Reject consecutive signs before currency symbol
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

    if (majorUnits > _maxSafeMajor ||
        (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
      throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
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

void runTestSuite(String name, dynamic parseFn, dynamic tryParseFn) {
  print('--- Testing $name ---');
  const conflictingSignCases = [
    '+-10',
    '-+10',
    '+¥-10',
    '-¥+10',
    '++10',
    '--10',
    '+¥+10',
    '-¥-10',
    '+-12.50',
    '-+12.50',
    '+¥-12.50',
    '-¥+12.50',
  ];

  for (final input in conflictingSignCases) {
    bool threwWithNegative = false;
    try {
      parseFn(input, allowNegative: true);
    } on FormatException {
      threwWithNegative = true;
    }
    assert(threwWithNegative, 'parseToMinorUnits should throw FormatException for "$input" (allowNegative: true)');

    bool threwWithoutNegative = false;
    try {
      parseFn(input, allowNegative: false);
    } on FormatException {
      threwWithoutNegative = true;
    }
    assert(threwWithoutNegative, 'parseToMinorUnits should throw FormatException for "$input" (allowNegative: false)');

    assert(tryParseFn(input, allowNegative: true) == null, 'tryParseToMinorUnits should return null for "$input" (allowNegative: true)');
    assert(tryParseFn(input, allowNegative: false) == null, 'tryParseToMinorUnits should return null for "$input" (allowNegative: false)');
  }
  print('  [OK] All 12 conflicting sign test cases passed in $name (48 assertions)!');
}

void main() {
  runTestSuite('Option 1 (State tracking & downstream validation)', Option1CurrencyUtils.parseToMinorUnits, Option1CurrencyUtils.tryParseToMinorUnits);
  runTestSuite('Option 2 (Explicit fast-fail multiple signs validation)', Option2CurrencyUtils.parseToMinorUnits, Option2CurrencyUtils.tryParseToMinorUnits);
  print('ALL COMPARISONS SUCCESSFUL!');
}
