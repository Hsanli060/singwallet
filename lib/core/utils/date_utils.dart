// lib/core/utils/date_utils.dart

/// Result of parsing a date/time string from OCR or text
class ParsedDateResult {
  final String occurredOn; // 'YYYY-MM-DD'
  final String? occurredAt; // UTC ISO-8601 string (e.g. '2026-10-22T06:30:15.000Z') or null
  final String precision; // 'second', 'minute', 'day'
  final String source; // 'ocr_extracted', 'suggested_today', 'user_selected'
  final String timezone; // 'Asia/Shanghai'
  final String matchedSubstring;

  const ParsedDateResult({
    required this.occurredOn,
    this.occurredAt,
    required this.precision,
    required this.source,
    this.timezone = 'Asia/Shanghai',
    this.matchedSubstring = '',
  });

  @override
  String toString() =>
      'ParsedDateResult(occurredOn: $occurredOn, occurredAt: $occurredAt, precision: $precision, source: $source)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedDateResult &&
          runtimeType == other.runtimeType &&
          occurredOn == other.occurredOn &&
          occurredAt == other.occurredAt &&
          precision == other.precision &&
          source == other.source &&
          timezone == other.timezone;

  @override
  int get hashCode => Object.hash(occurredOn, occurredAt, precision, source, timezone);
}

/// Utility for parsing and converting receipt dates and timestamps
class DateUtils {
  DateUtils._();

  static final RegExp _secondRegex = RegExp(
    r'(?:创建时间|支付时间|交易时间|扣款时间|时间)?[:：\s]*(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?\s*(\d{1,2})\s*[:：]\s*(\d{2})\s*[:：]\s*(\d{2})',
  );

  static final RegExp _minuteRegex = RegExp(
    r'(?:创建时间|支付时间|交易时间|扣款时间|时间)?[:：\s]*(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?\s*(\d{1,2})\s*[:：]\s*(\d{2})',
  );

  static final RegExp _monthDayMinuteRegex = RegExp(
    r'(?:创建时间|支付时间|交易时间|扣款时间|时间)?[:：\s]*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?\s*(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*(\d{2}))?',
  );

  static final RegExp _dayRegex = RegExp(
    r'(?:创建时间|支付时间|交易时间|扣款时间|时间)?[:：\s]*(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?',
  );

  /// Parses date and time from candidate receipt text.
  /// Strictly rejects invalid calendar dates (e.g. Feb 30th) and invalid times.
  static ParsedDateResult? parseReceiptDateTime(String text, {DateTime? now}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 1. Try second precision
    final secondMatch = _secondRegex.firstMatch(trimmed);
    if (secondMatch != null) {
      final y = int.tryParse(secondMatch.group(1) ?? '');
      final m = int.tryParse(secondMatch.group(2) ?? '');
      final d = int.tryParse(secondMatch.group(3) ?? '');
      final h = int.tryParse(secondMatch.group(4) ?? '');
      final min = int.tryParse(secondMatch.group(5) ?? '');
      final s = int.tryParse(secondMatch.group(6) ?? '');
      if (_isValidDateTime(y, m, d, h, min, s)) {
        final occurredOn = _formatYmd(y!, m!, d!);
        final occurredAt = toUtcIsoStringFromComponents(y, m, d, h!, min!, s!);
        return ParsedDateResult(
          occurredOn: occurredOn,
          occurredAt: occurredAt,
          precision: 'second',
          source: 'ocr_extracted',
          matchedSubstring: secondMatch.group(0) ?? '',
        );
      }
    }

    // 2. Try minute precision
    final minuteMatch = _minuteRegex.firstMatch(trimmed);
    if (minuteMatch != null) {
      final y = int.tryParse(minuteMatch.group(1) ?? '');
      final m = int.tryParse(minuteMatch.group(2) ?? '');
      final d = int.tryParse(minuteMatch.group(3) ?? '');
      final h = int.tryParse(minuteMatch.group(4) ?? '');
      final min = int.tryParse(minuteMatch.group(5) ?? '');
      if (_isValidDateTime(y, m, d, h, min, 0)) {
        final occurredOn = _formatYmd(y!, m!, d!);
        final occurredAt = toUtcIsoStringFromComponents(y, m, d, h!, min!, 0);
        return ParsedDateResult(
          occurredOn: occurredOn,
          occurredAt: occurredAt,
          precision: 'minute',
          source: 'ocr_extracted',
          matchedSubstring: minuteMatch.group(0) ?? '',
        );
      }
    }

    // 3. Try short month-day with hour-minute (inferred year)
    final shortMatch = _monthDayMinuteRegex.firstMatch(trimmed);
    if (shortMatch != null) {
      final currentYear = (now ?? DateTime.now()).year;
      final m = int.tryParse(shortMatch.group(1) ?? '');
      final d = int.tryParse(shortMatch.group(2) ?? '');
      final h = int.tryParse(shortMatch.group(3) ?? '');
      final min = int.tryParse(shortMatch.group(4) ?? '');
      final s = int.tryParse(shortMatch.group(5) ?? '') ?? 0;
      final hasSeconds = shortMatch.group(5) != null;
      if (_isValidDateTime(currentYear, m, d, h, min, s)) {
        final occurredOn = _formatYmd(currentYear, m!, d!);
        final occurredAt = toUtcIsoStringFromComponents(currentYear, m, d, h!, min!, s);
        return ParsedDateResult(
          occurredOn: occurredOn,
          occurredAt: occurredAt,
          precision: hasSeconds ? 'second' : 'minute',
          source: 'ocr_extracted',
          matchedSubstring: shortMatch.group(0) ?? '',
        );
      }
    }

    // 4. Try day precision (Date only) - only if no time was specified
    final hasTimePattern = RegExp(r'\d{1,2}:\d{2}').hasMatch(trimmed);
    if (!hasTimePattern) {
      final dayMatch = _dayRegex.firstMatch(trimmed);
      if (dayMatch != null) {
        final y = int.tryParse(dayMatch.group(1) ?? '');
        final m = int.tryParse(dayMatch.group(2) ?? '');
        final d = int.tryParse(dayMatch.group(3) ?? '');
        if (_isValidDate(y, m, d)) {
          final occurredOn = _formatYmd(y!, m!, d!);
          return ParsedDateResult(
            occurredOn: occurredOn,
            occurredAt: null, // Zero hallucination: do not invent hour/min
            precision: 'day',
            source: 'ocr_extracted',
            matchedSubstring: dayMatch.group(0) ?? '',
          );
        }
      }
    }

    return null;
  }

  /// Formats a DateTime to YYYY-MM-DD
  static String formatDate(DateTime dt) {
    return _formatYmd(dt.year, dt.month, dt.day);
  }

  /// Converts local date time components (default Asia/Shanghai UTC+8) to UTC ISO-8601 string
  static String toUtcIsoStringFromComponents(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second, {
    int offsetHours = 8,
  }) {
    final localAsUtc = DateTime.utc(year, month, day, hour, minute, second);
    final utc = localAsUtc.subtract(Duration(hours: offsetHours));
    return utc.toIso8601String();
  }

  /// Converts a local DateTime to UTC ISO-8601 string
  static String toUtcIsoString(DateTime localDt, {int offsetHours = 8}) {
    return toUtcIsoStringFromComponents(
      localDt.year,
      localDt.month,
      localDt.day,
      localDt.hour,
      localDt.minute,
      localDt.second,
      offsetHours: offsetHours,
    );
  }

  /// Generates a fallback result using today's date
  static ParsedDateResult fallbackToday({DateTime? now}) {
    final today = now ?? DateTime.now();
    return ParsedDateResult(
      occurredOn: formatDate(today),
      occurredAt: null,
      precision: 'day',
      source: 'suggested_today',
      timezone: 'Asia/Shanghai',
      matchedSubstring: '',
    );
  }

  static bool isValidDate(int? y, int? m, int? d) => _isValidDate(y, m, d);

  static bool isValidDateTime(int? y, int? m, int? d, int? h, int? min, int? s) =>
      _isValidDateTime(y, m, d, h, min, s);

  static bool _isValidDate(int? y, int? m, int? d) {
    if (y == null || m == null || d == null) return false;
    if (y < 1970 || y > 2100) return false;
    if (m < 1 || m > 12) return false;
    if (d < 1 || d > 31) return false;
    final dt = DateTime.utc(y, m, d);
    return dt.year == y && dt.month == m && dt.day == d;
  }

  static bool _isValidDateTime(int? y, int? m, int? d, int? h, int? min, int? s) {
    if (!_isValidDate(y, m, d)) return false;
    if (h == null || min == null || s == null) return false;
    if (h < 0 || h > 23) return false;
    if (min < 0 || min > 59) return false;
    if (s < 0 || s > 59) return false;
    return true;
  }

  static String _formatYmd(int y, int m, int d) {
    final yStr = y.toString().padLeft(4, '0');
    final mStr = m.toString().padLeft(2, '0');
    final dStr = d.toString().padLeft(2, '0');
    return '$yStr-$mStr-$dStr';
  }
}
