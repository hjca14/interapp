import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/full_screen_intent_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('interapp/full_screen_intent');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reports true when the platform confirms access', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'canUseFullScreenIntent');
          return true;
        });

    expect(await checkFullScreenIntentAccess(), isTrue);
  });

  test('reports false when the platform denies access', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);

    expect(await checkFullScreenIntentAccess(), isFalse);
  });

  test('a missing platform implementation fails safe to false', () async {
    // No handler registered at all (older platform, non-Android target, or
    // a plugin that never attached) — this must never throw or crash the
    // caller, it must simply behave as "no full-screen access".
    expect(await checkFullScreenIntentAccess(), isFalse);
  });

  test('a platform exception fails safe to false, never rethrown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'internal-detail'),
        );

    expect(await checkFullScreenIntentAccess(), isFalse);
  });

  test('a null platform result fails safe to false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await checkFullScreenIntentAccess(), isFalse);
  });
}
