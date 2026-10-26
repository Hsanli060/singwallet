// test/recognition/llm_bill_result_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/features/recognition/models/llm_bill_result.dart';

void main() {
  group('PaymentMethod Tests', () {
    test('Wechat subtypes: wallet, change fund, bank card with last4', () {
      final p1 = PaymentMethod.create(
        channel: PaymentChannel.wechat,
        subType: '钱包',
      );
      expect(p1.displayName, '微信 · 钱包');
      expect(p1.isBankCard, isFalse);

      final p2 = PaymentMethod.create(
        channel: PaymentChannel.wechat,
        subType: '零钱通',
      );
      expect(p2.displayName, '微信 · 零钱通');

      final p3 = PaymentMethod.create(
        channel: PaymentChannel.wechat,
        subType: '银行卡',
        bankName: '招商银行',
        cardLast4: '8848',
      );
      expect(p3.displayName, '微信 · 招商银行(8848)');
      expect(p3.isBankCard, isTrue);
      expect(p3.cardLast4, '8848');
    });

    test('Alipay subtypes: balance, yuebao, bank card with last4', () {
      final p1 = PaymentMethod.create(
        channel: PaymentChannel.alipay,
        subType: '余额',
      );
      expect(p1.displayName, '支付宝 · 余额');

      final p2 = PaymentMethod.create(
        channel: PaymentChannel.alipay,
        subType: '余额宝',
      );
      expect(p2.displayName, '支付宝 · 余额宝');

      final p3 = PaymentMethod.create(
        channel: PaymentChannel.alipay,
        subType: '银行卡',
        bankName: '建设银行',
        cardLast4: '1234',
      );
      expect(p3.displayName, '支付宝 · 建设银行(1234)');
    });

    test('UnionPay subtype: strictly bank card with last4', () {
      final p1 = PaymentMethod.create(
        channel: PaymentChannel.unionpay,
        subType: '银行卡',
        bankName: '中国工商银行',
        cardLast4: '5678',
      );
      expect(p1.displayName, '云闪付 · 中国工商银行(5678)');
      expect(p1.isBankCard, isTrue);
    });

    test('Strict validation throws on illegal combinations', () {
      // 微信不支持余额
      expect(
        () => PaymentMethod.create(channel: PaymentChannel.wechat, subType: '余额'),
        throwsA(isA<FormatException>()),
      );

      // 云闪付不支持钱包
      expect(
        () => PaymentMethod.create(channel: PaymentChannel.unionpay, subType: '钱包'),
        throwsA(isA<FormatException>()),
      );

      // 银行卡没有提供 4 位卡号
      expect(
        () => PaymentMethod.create(channel: PaymentChannel.wechat, subType: '银行卡'),
        throwsA(isA<FormatException>()),
      );

      // 银行卡卡号不是 4 位数字
      expect(
        () => PaymentMethod.create(
          channel: PaymentChannel.alipay,
          subType: '银行卡',
          cardLast4: '12',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('LlmBillResult Unit Tests', () {
    test('parses full structured JSON correctly with nested PaymentMethod', () {
      final json = {
        'amount': 70.00,
        'merchant': '杭州市拱墅区世臻便利店',
        'order_time': '2026-10-25 13:29:53',
        'order_id': '4200003143202610252738865252',
        'category': '日常购物',
        'payment': {
          'channel': '微信',
          'sub_type': '银行卡',
          'bank_name': '招商银行',
          'card_last_4': '8848',
        },
      };

      final result = LlmBillResult.fromJson(json);

      expect(result.amount, 70.00);
      expect(result.amountInCents, 7000);
      expect(result.merchant, '杭州市拱墅区世臻便利店');
      expect(result.orderId, '4200003143202610252738865252');
      expect(result.orderTime, DateTime(2026, 10, 25, 13, 29, 53));
      expect(result.category, BillCategory.shopping);
      expect(result.category.label, '日常购物');

      expect(result.payment.channel, PaymentChannel.wechat);
      expect(result.payment.subType, '银行卡');
      expect(result.payment.bankName, '招商银行');
      expect(result.payment.cardLast4, '8848');
      expect(result.payment.displayName, '微信 · 招商银行(8848)');
    });

    test('supports markdown code fence ```json with Alipay YuEBao', () {
      const raw = '''
```json
{
  "amount": 15.77,
  "merchant": "淘宝平台商户",
  "order_time": "2026-10-25 10:44:54",
  "order_id": "19190200000948642610251329513690",
  "category": "日常购物",
  "payment": {
    "channel": "支付宝",
    "sub_type": "余额宝"
  }
}
```
''';

      final result = LlmBillResult.fromJsonString(raw);
      expect(result.amount, 15.77);
      expect(result.merchant, '淘宝平台商户');
      expect(result.payment.channel, PaymentChannel.alipay);
      expect(result.payment.subType, '余额宝');
      expect(result.payment.displayName, '支付宝 · 余额宝');
    });

    test('jsonSchema contains all required properties and strict enum constraints', () {
      final schema = LlmBillResult.jsonSchema;
      expect(schema['type'], 'object');
      final props = schema['properties'] as Map<String, dynamic>;

      expect(props.containsKey('payment'), isTrue);
      final paymentProps = props['payment']['properties'] as Map<String, dynamic>;
      expect(paymentProps['channel']['enum'], containsAll(['微信', '支付宝', '云闪付']));
      expect(paymentProps['sub_type']['enum'], containsAll(['钱包', '零钱通', '余额', '余额宝', '银行卡']));
    });
  });
}
