import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/core/utils/date_utils.dart';

void main() {
  test('Check date parsing', () {
    final reg = RegExp(
      r'(?:创建时间|支付时间|交易时间|扣款时间|时间)?[:：\s]*(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?\s*(\d{1,2})\s*[:：]\s*(\d{2})\s*(?:[:：]\s*(\d{2}))?',
    );
    final samples = [
      '2026 年 10 月 25 日 18 ： 41 ： 54',
      '2026 年 10 月 26 日 08 ： 01 ： 25',
      '2026 年 10 月 25 日 14 ： 19 ： 38',
      '2026 年 10 月 25 日 13 ： 29 ： 53',
    ];
    for (final s in samples) {
      final m = reg.firstMatch(s);
      print('Matching: "$s" -> ${m != null ? "${m.group(1)}-${m.group(2)}-${m.group(3)} ${m.group(4)}:${m.group(5)}:${m.group(6)}" : "NULL"}');
    }
  });
}
