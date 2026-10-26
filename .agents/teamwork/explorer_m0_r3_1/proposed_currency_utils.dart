/// Monetary calculation utilities using integer minor currency units (cents / 分).
///
/// Ensures 100% precision arithmetic without IEEE 754 floating-point drift.
class CurrencyUtils {
  CurrencyUtils._();

  /// Maximum major currency units that can be safely converted to minor units (cents)
  /// without overflowing a 64-bit signed integer (2^63 - 1 = 9223372036854775807).
  static const int _maxSafeMajor = 92233720368547758; // (2^63 - 1) ~/ 100

  /// Maximum minor units allowed when [majorUnits] equals [_maxSafeMajor].
  static const int _maxMinorForBoundary = 7; // (2^63 - 1) % 100

  /// Public constant for maximum safe major units before 64-bit integer overflow.
  static const int maxSafeMajor = _maxSafeMajor;

  /// Public constant for maximum safe minor units on the 64-bit integer boundary.
  static const int maxMinorForBoundary = _maxMinorForBoundary;

  /// Converts cents (minor currency unit) to display string (e.g. 2890 -> "28.90").
  static String centsToYuanString(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absCents = cents.abs();
    final yuan = absCents ~/ 100;
    final centRemainder = absCents % 100;
    return '$sign$yuan.${centRemainder.toString().padLeft(2, '0')}';
  }

  /// Canonical alias for [centsToYuanString].
  static String formatMinorUnits(int minorUnits) => centsToYuanString(minorUnits);

  /// Parses an amount string to integer minor currency units (cents/分).
  ///
  /// Handles common formats, OCR outputs, and user input edge cases:
  /// - Standard: `"28.90"` -> `2890`, `"28.9"` -> `2890`, `"28"` -> `2800`
  /// - Trailing decimal: `"12."` -> `1200`
  /// - Leading decimal: `".50"` -> `50`, `".5"` -> `50`, `".05"` -> `5`
  /// - Thousands grouping: `"1,234.50"` -> `123450`
  /// - Currency symbols: `"¥28.90"`, `"$28.90"`, `"CNY 28.90"` -> `2890`
  /// - Negative amounts: `"-12.50"`, `"-¥12.50"`, `"-.50"` -> negative cents (when [allowNegative] is true)
  ///
  /// Throws [FormatException] if the input cannot be parsed or represents an
  /// invalid currency amount (e.g., `""`, `"."`, `"12.34.56"`, `"12.ab"`),
  /// or if the parsed amount exceeds 64-bit signed integer limits ($2^{63} - 1$).
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
    bool hasExplicitSign = false;
    if (trimmed.startsWith('-')) {
      isNegative = true;
      hasExplicitSign = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      hasExplicitSign = true;
      trimmed = trimmed.substring(1).trim();
    }

    if (stripCurrencySymbols) {
      trimmed = trimmed.replaceFirst(
        RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false),
        '',
      );
      if (!hasExplicitSign) {
        if (trimmed.startsWith('-')) {
          isNegative = true;
          hasExplicitSign = true;
          trimmed = trimmed.substring(1).trim();
        } else if (trimmed.startsWith('+')) {
          hasExplicitSign = true;
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

    // Explicit 64-bit integer overflow protection:
    // In 64-bit signed two's complement integer arithmetic, max positive value is
    // 2^63 - 1 = 9223372036854775807 cents = 92233720368547758 * 100 + 7.
    // Inputs exceeding this boundary silently wrap around to negative numbers.
    if (majorUnits > _maxSafeMajor ||
        (majorUnits == _maxSafeMajor && minorUnits > _maxMinorForBoundary)) {
      throw FormatException('Currency amount exceeds 64-bit integer limit: "$input"');
    }

    final total = majorUnits * 100 + minorUnits;
    return isNegative ? -total : total;
  }

  /// Attempts to parse [input] to minor currency units, returning `null` on failure.
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

  /// Backward compatible wrapper around [parseToMinorUnits].
  static int yuanStringToCents(String input, {bool allowNegative = false}) {
    return parseToMinorUnits(input, allowNegative: allowNegative);
  }
}
