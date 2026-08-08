import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/pages/dialer_page.dart';

void main() {
  testWidgets('displays the dialer keypad', (tester) async {
    // The keypad's GridView disables scrolling (NeverScrollableScrollPhysics),
    // so every key must fit on screen at once. The default test surface
    // (800x600, much wider than tall) doesn't leave enough height for all 4
    // rows and silently drops the last row from the widget tree — use a
    // phone-shaped viewport instead, matching how the app is actually used.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DialerPage(controller: DialerController()))));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Digite o número'), findsOneWidget);
  });
}
