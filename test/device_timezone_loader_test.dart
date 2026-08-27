import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('interapp/device_timezone');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('timezone abstraction preserves a valid platform identifier', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getIdentifier');
          return 'America/Recife';
        });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(timezoneLoaderProvider)(), 'America/Recife');
  });

  for (final result in <String?>[null, '', '   ']) {
    test('timezone abstraction rejects ${result ?? 'null'}', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => result);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(timezoneLoaderProvider)(),
        throwsA(isA<TimezoneUnavailableException>()),
      );
    });
  }

  test('platform failures are sanitized', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'internal-detail'),
        );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container.read(timezoneLoaderProvider)(),
      throwsA(isA<TimezoneUnavailableException>()),
    );
  });
}
