// test/core/utils/date_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/utils/date_utils.dart';

void main() {
  group('DateUtils receipt timestamp parsing', () {
    test('Standard full timestamp with seconds parses to second precision', () {
      final res = DateUtils.parseReceiptDateTime('支付时间：2026-10-22 14:30:15');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, '2026-10-22T06:30:15.000Z');
      expect(res.precision, 'second');
      expect(res.source, 'ocr_extracted');
      expect(res.timezone, 'Asia/Shanghai');
    });

    test('Minute precision timestamp has 00 seconds and minute precision', () {
      final res = DateUtils.parseReceiptDateTime('创建时间: 2026/10/22 14:35');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, '2026-10-22T06:35:00.000Z');
      expect(res.precision, 'minute');
      expect(res.source, 'ocr_extracted');
    });

    test('Chinese character date format (年月日) parses correctly', () {
      final res = DateUtils.parseReceiptDateTime('交易时间 2026年10月22日 09:15:20');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, '2026-10-22T01:15:20.000Z');
      expect(res.precision, 'second');
    });

    test('Date only format has occurredAt null (no hallucinated time)', () {
      final res = DateUtils.parseReceiptDateTime('2026-10-22');
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, isNull);
      expect(res.precision, 'day');
      expect(res.source, 'ocr_extracted');
    });

    test('Short month-day with hour-minute infers current year', () {
      final now = DateTime(2026, 10, 22);
      final res = DateUtils.parseReceiptDateTime('10月22日 14:30', now: now);
      expect(res, isNotNull);
      expect(res!.occurredOn, '2026-10-22');
      expect(res.occurredAt, '2026-10-22T06:30:00.000Z');
      expect(res.precision, 'minute');
    });

    test('Invalid calendar date (e.g. Feb 30th) returns null safely', () {
      expect(DateUtils.parseReceiptDateTime('2026-02-30 12:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('2026-13-01 12:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('9999-99-99'), isNull);
      expect(DateUtils.parseReceiptDateTime('abc123notadate'), isNull);
    });

    test('Invalid time values (hour > 23, minute > 59) return null safely', () {
      expect(DateUtils.parseReceiptDateTime('2026-10-22 25:00:00'), isNull);
      expect(DateUtils.parseReceiptDateTime('2026-10-22 14:65:00'), isNull);
    });

    test('fallbackToday returns today date with day precision and suggested_today source', () {
      final now = DateTime(2026, 10, 22, 18, 0, 0);
      final res = DateUtils.fallbackToday(now: now);
      expect(res.occurredOn, '2026-10-22');
      expect(res.occurredAt, isNull);
      expect(res.precision, 'day');
      expect(res.source, 'suggested_today');
    });
  });
}
