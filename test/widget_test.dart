import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/pages/dialer_page.dart';

void main() {
  testWidgets('displays the dialer keypad', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DialerPage(controller: DialerController()))));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Digite o número'), findsOneWidget);
  });
}
