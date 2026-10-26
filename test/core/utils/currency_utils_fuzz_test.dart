import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/native/currency_utils.dart' as native_utils;
import 'package:singwallet/core/utils/currency_utils.dart';

void main() {
  group('CurrencyUtils 50,000 Fuzz & Property-Based Stress Test', () {
    final random = Random(42); // Deterministic seed for reproducibility

    // BigInt oracle for exact mathematical validation
    BigInt? exactOracle(
      String input, {
      bool allowNegative = false,
      bool stripCurrencySymbols = true,
      bool roundSubUnits = false,
    }) {
      var s = input.trim();
      if (s.isEmpty) return null;

      bool isNeg = false;
      bool hasLeadSign = false;
      if (s.startsWith('-')) {
        isNeg = true;
        hasLeadSign = true;
        s = s.substring(1).trim();
      } else if (s.startsWith('+')) {
        hasLeadSign = true;
        s = s.substring(1).trim();
      }

      if (stripCurrencySymbols) {
        final sym = RegExp(r'^(?:[¥￥$€£]|CNY|RMB|USD)\s*', caseSensitive: false);
        s = s.replaceFirst(sym, '');
        if (!hasLeadSign) {
          if (s.startsWith('-')) {
            isNeg = true;
            hasLeadSign = true;
            s = s.substring(1).trim();
          } else if (s.startsWith('+')) {
            hasLeadSign = true;
            s = s.substring(1).trim();
          }
        }
      }

      s = s.replaceAll(',', '').replaceAll(' ', '');
      if (s.isEmpty || s == '.') return null;
      if (isNeg && !allowNegative) return null;

      final parts = s.split('.');
      if (parts.length > 2) return null;

      final intPart = parts[0];
      BigInt major = BigInt.zero;
      if (intPart.isNotEmpty) {
        if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
        try {
          major = BigInt.parse(intPart);
        } catch (_) {
          return null;
        }
      }

      BigInt minor = BigInt.zero;
      if (parts.length == 2) {
        final decPart = parts[1];
        if (decPart.isNotEmpty) {
          if (!RegExp(r'^\d+$').hasMatch(decPart)) return null;
          if (decPart.length == 1) {
            minor = BigInt.from(int.parse(decPart) * 10);
          } else if (decPart.length == 2) {
            minor = BigInt.from(int.parse(decPart));
          } else {
            final base = int.parse(decPart.substring(0, 2));
            if (roundSubUnits) {
              final nextDigit = int.parse(decPart[2]);
              minor = BigInt.from(nextDigit >= 5 ? base + 1 : base);
            } else {
              minor = BigInt.from(base);
            }
          }
        }
      }

      final total = major * BigInt.from(100) + minor;
      return isNeg ? -total : total;
    }

    test('1. Category A: 10,000 Valid Standard Amounts Oracle Match & Round-Trip', () {
      final currencyPrefixes = ['', '¥', '￥', r'$', '€', '£', 'CNY ', 'RMB ', 'USD '];
      final maxInt64 = BigInt.parse('9223372036854775807');
      final minInt64 = -maxInt64;

      for (int i = 0; i < 10000; i++) {
        final allowNeg = random.nextBool();
        final isNeg = allowNeg && random.nextBool();
        final signStr = isNeg ? '-' : (random.nextBool() ? '+' : '');
        final prefix = currencyPrefixes[random.nextInt(currencyPrefixes.length)];

        // Generate major up to reasonable financial limits (0 to 1,000,000,000)
        final major = random.nextInt(1000000000);
        final formatChoice = random.nextInt(4);

        String amountStr;
        if (formatChoice == 0) {
          // Integer only
          amountStr = '$signStr$prefix$major';
        } else if (formatChoice == 1) {
          // 1 decimal place
          amountStr = '$signStr$prefix$major.${random.nextInt(10)}';
        } else if (formatChoice == 2) {
          // 2 decimal places
          amountStr = '$signStr$prefix$major.${random.nextInt(100).toString().padLeft(2, '0')}';
        } else {
          // With commas
          final majorStr = major.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]},',
              );
          amountStr = '$signStr$prefix$majorStr.${random.nextInt(100).toString().padLeft(2, '0')}';
        }

        final expectedBig = exactOracle(amountStr, allowNegative: allowNeg);
        final actual = CurrencyUtils.tryParseToMinorUnits(amountStr, allowNegative: allowNeg);

        if (expectedBig == null || expectedBig > maxInt64 || expectedBig < minInt64) {
          expect(actual, isNull, reason: 'Expected overflow or null for $amountStr');
        } else {
          expect(actual, isNotNull, reason: 'Failed to parse valid string: $amountStr');
          expect(actual, expectedBig.toInt(), reason: 'Oracle mismatch for: $amountStr');

          // Sign preservation invariant
          if (expectedBig > BigInt.zero) {
            expect(actual! > 0, isTrue, reason: 'Positive wrapped around for $amountStr');
          } else if (expectedBig < BigInt.zero) {
            expect(actual! < 0, isTrue, reason: 'Negative wrapped around for $amountStr');
          }

          // Invariant: centsToYuanString produces valid string that parses to same cents
          final formatted = CurrencyUtils.centsToYuanString(actual!);
          final reparsed = CurrencyUtils.parseToMinorUnits(formatted, allowNegative: true);
          expect(reparsed, actual, reason: 'Round-trip failure on $amountStr -> $formatted');
        }
      }
    });

    test('2. Category B: 10,000 Boundary & Overflow Stress (No Silent Wrap-Around)', () {
      const boundaryBase = 92233720368547758; // _maxSafeMajor
      final maxInt64 = BigInt.parse('9223372036854775807');
      final minInt64 = -maxInt64;

      for (int i = 0; i < 10000; i++) {
        // Delta between -5 and +5 major units around boundary
        final deltaMajor = random.nextInt(11) - 5;
        final testMajor = boundaryBase + deltaMajor;
        final testCents = random.nextInt(100);
        final allowNeg = random.nextBool();
        final isNeg = allowNeg && random.nextBool();
        final signStr = isNeg ? '-' : '';

        final input = '$signStr$testMajor.${testCents.toString().padLeft(2, '0')}';

        final expectedBig = exactOracle(input, allowNegative: allowNeg);
        int? result;
        bool threwException = false;
        try {
          result = CurrencyUtils.parseToMinorUnits(input, allowNegative: allowNeg);
        } on FormatException {
          threwException = true;
        } catch (e) {
          fail('Uncaught non-FormatException: $e for input "$input"');
        }

        final tryResult = CurrencyUtils.tryParseToMinorUnits(input, allowNegative: allowNeg);
        expect(tryResult, result, reason: 'tryParse mismatch with parse for "$input"');

        if (expectedBig == null || expectedBig > maxInt64 || expectedBig < minInt64) {
          // Must throw FormatException and tryResult must be null
          expect(threwException, isTrue, reason: 'Should have thrown FormatException for overflow: "$input"');
          expect(result, isNull);
        } else {
          expect(threwException, isFalse, reason: 'Threw unexpectedly on valid boundary: "$input"');
          expect(result, expectedBig.toInt());
          // CRITICAL INVARIANT: verify no silent integer wrap-around (e.g. positive became negative)
          if (expectedBig > BigInt.zero) {
            expect(result! > 0, isTrue, reason: 'Silent wrap-around detected: positive became negative for "$input"');
          } else if (expectedBig < BigInt.zero) {
            expect(result! < 0, isTrue, reason: 'Silent wrap-around detected: negative became positive for "$input"');
          }
        }
      }
    });

    test('3. Category C: 10,000 Massive Integer & Exponent Strings Fuzzing', () {
      final specialScientific = ['1e10', '2.5e6', '1e-5', '1E+18', '9.999999e20', 'NaN', 'Infinity', '-Infinity'];

      for (int i = 0; i < 10000; i++) {
        String testStr;
        if (i < specialScientific.length) {
          testStr = specialScientific[i];
        } else {
          // Generate massive string of 18 to 100 digits
          final digitCount = 18 + random.nextInt(83);
          final buffer = StringBuffer();
          if (random.nextBool()) buffer.write('-');
          for (int d = 0; d < digitCount; d++) {
            buffer.write(random.nextInt(10));
          }
          if (random.nextBool()) {
            buffer.write('.');
            buffer.write(random.nextInt(100));
          }
          testStr = buffer.toString();
        }

        final allowNeg = random.nextBool();
        try {
          final res = CurrencyUtils.tryParseToMinorUnits(testStr, allowNegative: allowNeg);
          // If it parsed, it must NOT have wrapped around
          if (res != null) {
            if (testStr.startsWith('-') && !allowNeg) {
              fail('Negative allowed when allowNegative is false for "$testStr"');
            }
          }
        } catch (e) {
          fail('CurrencyUtils.tryParseToMinorUnits threw uncaught exception $e on input "$testStr"');
        }

        try {
          CurrencyUtils.parseToMinorUnits(testStr, allowNegative: allowNeg);
        } on FormatException {
          // Expected for invalid/overflow
        } catch (e) {
          fail('CurrencyUtils.parseToMinorUnits threw non-FormatException $e on input "$testStr"');
        }
      }
    });

    test('4. Category D: 10,000 Adversarial Malformed Strings Fuzzing', () {
      const adversarialTokens = [
        '+', '-', '¥', '￥', r'$', '€', '£', 'CNY', 'RMB', 'USD',
        '.', ',', ' ', '\t', '\n', '\x00', 'a', 'x', '!', '@', '#',
        '0', '1', '9', 'e', 'E', 'NaN', 'null', 'undefined'
      ];

      for (int i = 0; i < 10000; i++) {
        // Build random adversarial token sequences
        final length = 1 + random.nextInt(15);
        final buffer = StringBuffer();
        for (int k = 0; k < length; k++) {
          buffer.write(adversarialTokens[random.nextInt(adversarialTokens.length)]);
        }
        final testStr = buffer.toString();
        final allowNeg = random.nextBool();

        int? tryRes;
        try {
          tryRes = CurrencyUtils.tryParseToMinorUnits(testStr, allowNegative: allowNeg);
        } catch (e) {
          fail('Uncaught exception in tryParseToMinorUnits for "$testStr": $e');
        }

        try {
          final parseRes = CurrencyUtils.parseToMinorUnits(testStr, allowNegative: allowNeg);
          expect(parseRes, tryRes);
          // Invariant: If allowNegative is false, parseRes must be >= 0
          if (!allowNeg) {
            expect(parseRes >= 0, isTrue);
          }
        } on FormatException {
          expect(tryRes, isNull, reason: 'tryParseToMinorUnits was not null when parse threw FormatException for "$testStr"');
        } catch (e) {
          fail('Uncaught non-FormatException in parseToMinorUnits for "$testStr": $e');
        }
      }
    });

    test('5. Category E: 10,000 Sub-cent Rounding Invariants & Precision Fuzzing', () {
      for (int i = 0; i < 10000; i++) {
        final major = random.nextInt(1000000);
        // Sub-cents with 3 to 6 digits
        final decimalDigits = 3 + random.nextInt(4);
        final decBuffer = StringBuffer();
        for (int d = 0; d < decimalDigits; d++) {
          decBuffer.write(random.nextInt(10));
        }
        final testStr = '$major.${decBuffer.toString()}';

        final truncBig = exactOracle(testStr, roundSubUnits: false);
        final roundBig = exactOracle(testStr, roundSubUnits: true);

        final truncVal = CurrencyUtils.tryParseToMinorUnits(testStr, roundSubUnits: false);
        final roundVal = CurrencyUtils.tryParseToMinorUnits(testStr, roundSubUnits: true);

        expect(truncVal, isNotNull);
        expect(roundVal, isNotNull);
        expect(truncVal, truncBig?.toInt());
        expect(roundVal, roundBig?.toInt());

        // Invariant: abs(roundVal - truncVal) <= 1
        expect((roundVal! - truncVal!).abs() <= 1, isTrue,
            reason: 'Rounding delta exceeded 1 cent for $testStr (round: $roundVal, trunc: $truncVal)');

        // Also verify native_utils re-export
        final nativeVal = native_utils.CurrencyUtils.tryParseToMinorUnits(testStr, roundSubUnits: true);
        expect(nativeVal, roundVal);
      }
    });
  });
}
