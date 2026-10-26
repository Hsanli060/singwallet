// Proposed unit test cases for CurrencyUtils 64-bit overflow and sign validation.
// To be appended to test/core/utils/currency_utils_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/utils/currency_utils.dart';

void main() {
  group('CurrencyUtils 64-bit Integer Overflow & Sign Edge Cases', () {
    test('Boundary: maximum safe 64-bit minor units (2^63 - 1)', () {
      // 92233720368547758.07 * 100 = 9223372036854775807 (int64 max)
      const maxInt64 = 9223372036854775807;
      expect(CurrencyUtils.parseToMinorUnits('92233720368547758.07'), maxInt64);
      expect(CurrencyUtils.tryParseToMinorUnits('92233720368547758.07'), maxInt64);

      // Negative maximum safe 64-bit minor units
      expect(
        CurrencyUtils.parseToMinorUnits('-92233720368547758.07', allowNegative: true),
        -maxInt64,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('-92233720368547758.07', allowNegative: true),
        -maxInt64,
      );
    });

    test('Boundary: overflow by 1 minor unit (92233720368547758.08) throws FormatException', () {
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547758.08'),
        throwsFormatException,
      );
      expect(CurrencyUtils.tryParseToMinorUnits('92233720368547758.08'), isNull);

      expect(
        () => CurrencyUtils.parseToMinorUnits('-92233720368547758.08', allowNegative: true),
        throwsFormatException,
      );
      expect(CurrencyUtils.tryParseToMinorUnits('-92233720368547758.08', allowNegative: true), isNull);
    });

    test('Boundary: major unit overflow (92233720368547759) throws FormatException', () {
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547759'),
        throwsFormatException,
      );
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547759.00'),
        throwsFormatException,
      );
      expect(CurrencyUtils.tryParseToMinorUnits('92233720368547759.00'), isNull);
    });

    test('Adversarial: max 64-bit integer as major unit (9223372036854775807) wraps without guard', () {
      expect(
        () => CurrencyUtils.parseToMinorUnits('9223372036854775807'),
        throwsFormatException,
      );
      expect(CurrencyUtils.tryParseToMinorUnits('9223372036854775807'), isNull);

      expect(
        () => CurrencyUtils.parseToMinorUnits('-9223372036854775807', allowNegative: true),
        throwsFormatException,
      );
      expect(CurrencyUtils.tryParseToMinorUnits('-9223372036854775807', allowNegative: true), isNull);
    });

    test('Sub-cent rounding at 64-bit boundary', () {
      // 92233720368547758.074 without rounding -> safe (ends in .07)
      expect(
        CurrencyUtils.parseToMinorUnits('92233720368547758.074', roundSubUnits: true),
        9223372036854775807,
      );

      // 92233720368547758.075 with rounding -> rounds to .08, triggers overflow guard
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547758.075', roundSubUnits: true),
        throwsFormatException,
      );
    });

    test('Conflicting mixed sign prefixes throw FormatException', () {
      expect(() => CurrencyUtils.parseToMinorUnits('+-10', allowNegative: true), throwsFormatException);
      expect(CurrencyUtils.tryParseToMinorUnits('+-10', allowNegative: true), isNull);

      expect(() => CurrencyUtils.parseToMinorUnits('+¥-10', allowNegative: true), throwsFormatException);
      expect(CurrencyUtils.tryParseToMinorUnits('+¥-10', allowNegative: true), isNull);

      expect(() => CurrencyUtils.parseToMinorUnits('-+10', allowNegative: true), throwsFormatException);
      expect(() => CurrencyUtils.parseToMinorUnits('--10', allowNegative: true), throwsFormatException);
      expect(() => CurrencyUtils.parseToMinorUnits('++10', allowNegative: true), throwsFormatException);
    });
  });
}
