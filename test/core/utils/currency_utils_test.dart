import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/currency_utils.dart' as native_utils;
import 'package:singwallet/core/utils/currency_utils.dart';

void main() {
  group('CurrencyUtils.parseToMinorUnits & yuanStringToCents', () {
    test('Standard positive amounts', () {
      expect(CurrencyUtils.parseToMinorUnits('28.90'), 2890);
      expect(CurrencyUtils.parseToMinorUnits('28.9'), 2890);
      expect(CurrencyUtils.parseToMinorUnits('28'), 2800);
      expect(CurrencyUtils.parseToMinorUnits('0.05'), 5);
      expect(CurrencyUtils.parseToMinorUnits('0.5'), 50);
      expect(CurrencyUtils.parseToMinorUnits('0'), 0);
      expect(CurrencyUtils.parseToMinorUnits('0.00'), 0);
    });

    test('Edge case: trailing decimal point ("12.", "28.")', () {
      expect(CurrencyUtils.parseToMinorUnits('12.'), 1200);
      expect(CurrencyUtils.parseToMinorUnits('28.'), 2800);
      expect(CurrencyUtils.parseToMinorUnits('0.'), 0);
      expect(CurrencyUtils.yuanStringToCents('12.'), 1200);
      expect(native_utils.CurrencyUtils.parseToMinorUnits('12.'), 1200);
    });

    test('Edge case: leading decimal point (".50", ".5", ".05")', () {
      expect(CurrencyUtils.parseToMinorUnits('.50'), 50);
      expect(CurrencyUtils.parseToMinorUnits('.5'), 50);
      expect(CurrencyUtils.parseToMinorUnits('.05'), 5);
      expect(CurrencyUtils.parseToMinorUnits('.00'), 0);
      expect(CurrencyUtils.yuanStringToCents('.50'), 50);
      expect(native_utils.CurrencyUtils.parseToMinorUnits('.50'), 50);
    });

    test('Thousands grouping separators', () {
      expect(CurrencyUtils.parseToMinorUnits('1,234.50'), 123450);
      expect(CurrencyUtils.parseToMinorUnits('1,234,567.89'), 123456789);
      expect(CurrencyUtils.parseToMinorUnits('1,000.'), 100000);
    });

    test('Currency symbols and whitespace stripping', () {
      expect(CurrencyUtils.parseToMinorUnits('¥28.90'), 2890);
      expect(CurrencyUtils.parseToMinorUnits('￥ 100.00'), 10000);
      expect(CurrencyUtils.parseToMinorUnits('\$ 12.50'), 1250);
      expect(CurrencyUtils.parseToMinorUnits('CNY 50.00'), 5000);
      expect(CurrencyUtils.parseToMinorUnits('RMB 99.9'), 9990);
    });

    test('Negative amount handling', () {
      expect(
        CurrencyUtils.parseToMinorUnits('-28.90', allowNegative: true),
        -2890,
      );
      expect(
        CurrencyUtils.parseToMinorUnits('-12.', allowNegative: true),
        -1200,
      );
      expect(
        CurrencyUtils.parseToMinorUnits('-.50', allowNegative: true),
        -50,
      );
      expect(
        CurrencyUtils.parseToMinorUnits('-¥12.50', allowNegative: true),
        -1250,
      );

      expect(
        () => CurrencyUtils.parseToMinorUnits('-28.90', allowNegative: false),
        throwsFormatException,
      );
      expect(
        () => CurrencyUtils.parseToMinorUnits('-.50', allowNegative: false),
        throwsFormatException,
      );
    });

    test('Sub-cent fractional truncation vs rounding', () {
      // Default: truncation
      expect(CurrencyUtils.parseToMinorUnits('12.344'), 1234);
      expect(CurrencyUtils.parseToMinorUnits('12.349'), 1234);

      // Rounding enabled
      expect(CurrencyUtils.parseToMinorUnits('12.344', roundSubUnits: true), 1234);
      expect(CurrencyUtils.parseToMinorUnits('12.345', roundSubUnits: true), 1235);
      expect(CurrencyUtils.parseToMinorUnits('12.349', roundSubUnits: true), 1235);
    });

    test('Malformed inputs throwing FormatException', () {
      final invalidCases = [
        '',
        '   ',
        '.',
        '-.',
        '+.',
        '-',
        '12.34.56',
        '12.ab',
        'foo',
        '12..34',
        '--12.50',
        '+-10',
        '-+10',
        '+¥-10',
        '-¥+10',
      ];

      for (final invalid in invalidCases) {
        expect(
          () => CurrencyUtils.parseToMinorUnits(invalid),
          throwsFormatException,
          reason: 'Should throw FormatException for "$invalid"',
        );
      }
    });

    test('tryParseToMinorUnits returns null on invalid without throwing', () {
      expect(CurrencyUtils.tryParseToMinorUnits(null), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits(''), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('.'), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('abc'), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('12.34'), 1234);
      expect(CurrencyUtils.tryParseToMinorUnits('.50'), 50);
      expect(CurrencyUtils.tryParseToMinorUnits('12.'), 1200);
      expect(CurrencyUtils.tryParseToMinorUnits('92233720368547758.08'), isNull);
      expect(CurrencyUtils.tryParseToMinorUnits('+-10'), isNull);
    });

    test('centsToYuanString format round-trip', () {
      expect(CurrencyUtils.centsToYuanString(2890), '28.90');
      expect(CurrencyUtils.centsToYuanString(5), '0.05');
      expect(CurrencyUtils.centsToYuanString(0), '0.00');
      expect(CurrencyUtils.centsToYuanString(-1250), '-12.50');
      expect(CurrencyUtils.formatMinorUnits(1200), '12.00');
    });

    test('64-bit integer boundary and overflow handling', () {
      // Maximum safe 64-bit signed minor unit boundary:
      // 92233720368547758 * 100 + 7 = 9223372036854775807 (2^63 - 1)
      expect(
        CurrencyUtils.parseToMinorUnits('92233720368547758.07'),
        9223372036854775807,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('92233720368547758.07'),
        9223372036854775807,
      );
      expect(
        native_utils.CurrencyUtils.parseToMinorUnits('92233720368547758.07'),
        9223372036854775807,
      );

      // Negative boundary with allowNegative: true
      expect(
        CurrencyUtils.parseToMinorUnits('-92233720368547758.07', allowNegative: true),
        -9223372036854775807,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('-92233720368547758.07', allowNegative: true),
        -9223372036854775807,
      );

      // Negative boundary without allowNegative: false throws FormatException
      expect(
        () => CurrencyUtils.parseToMinorUnits('-92233720368547758.07', allowNegative: false),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('-92233720368547758.07', allowNegative: false),
        isNull,
      );

      // Exceeding 64-bit signed integer boundary by 1 minor unit (9223372036854775808):
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547758.08'),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('92233720368547758.08'),
        isNull,
      );

      // Major units alone exceeding 64-bit capacity when multiplied by 100:
      expect(
        () => CurrencyUtils.parseToMinorUnits('9223372036854775807'),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('9223372036854775807'),
        isNull,
      );

      // Value with major units > max safe major units:
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547759.00'),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('92233720368547759.00'),
        isNull,
      );

      // Extremely large integer exceeding 64-bit int parsing capacity entirely:
      expect(
        () => CurrencyUtils.parseToMinorUnits('9999999999999999999999'),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('9999999999999999999999'),
        isNull,
      );

      // Sub-cent rounding at 64-bit boundary
      expect(
        CurrencyUtils.parseToMinorUnits('92233720368547758.069', roundSubUnits: true),
        9223372036854775807,
      );
      expect(
        () => CurrencyUtils.parseToMinorUnits('92233720368547758.075', roundSubUnits: true),
        throwsFormatException,
      );
      expect(
        CurrencyUtils.tryParseToMinorUnits('92233720368547758.075', roundSubUnits: true),
        isNull,
      );
    });

    test('Malformed conflicting signs rejection', () {
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
        expect(
          () => CurrencyUtils.parseToMinorUnits(input, allowNegative: true),
          throwsFormatException,
          reason: 'parseToMinorUnits should throw FormatException for conflicting signs "$input"',
        );
        expect(
          () => CurrencyUtils.parseToMinorUnits(input, allowNegative: false),
          throwsFormatException,
          reason: 'parseToMinorUnits should throw FormatException for conflicting signs "$input"',
        );
        expect(
          CurrencyUtils.tryParseToMinorUnits(input, allowNegative: true),
          isNull,
          reason: 'tryParseToMinorUnits should return null for conflicting signs "$input"',
        );
        expect(
          CurrencyUtils.tryParseToMinorUnits(input, allowNegative: false),
          isNull,
          reason: 'tryParseToMinorUnits should return null for conflicting signs "$input"',
        );
        expect(
          native_utils.CurrencyUtils.tryParseToMinorUnits(input, allowNegative: true),
          isNull,
          reason: 'native_utils should return null for conflicting signs "$input"',
        );
      }
    });
  });
}
