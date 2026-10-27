import 'package:flutter_test/flutter_test.dart';
import 'package:singwallet/main.dart';

void main() {
  testWidgets('SingWalletApp launches and displays core title', (WidgetTester tester) async {
    await tester.pumpWidget(const SingWalletApp());
    expect(find.text('SingWallet'), findsOneWidget);
  });
}
