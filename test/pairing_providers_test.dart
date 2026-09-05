import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/android_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/data/repositories/ios_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/data/repositories/not_implemented_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/presentation/providers/pairing_providers.dart';

void main() {
  group('selectBleOnboardingTransport', () {
    test('Android with a configured PoP gets the real Android transport', () {
      final transport = selectBleOnboardingTransport(
        platform: TargetPlatform.android,
        developmentPop: 'dev-pop',
      );
      expect(transport, isA<AndroidBleOnboardingTransport>());
    });

    test('iOS with a configured PoP gets the real iOS transport', () {
      final transport = selectBleOnboardingTransport(
        platform: TargetPlatform.iOS,
        developmentPop: 'dev-pop',
      );
      expect(transport, isA<IOSBleOnboardingTransport>());
    });

    test('a missing PoP falls back to unavailable on Android', () {
      final transport = selectBleOnboardingTransport(
        platform: TargetPlatform.android,
        developmentPop: '',
      );
      expect(transport, isA<NotImplementedBleOnboardingTransport>());
    });

    test('a missing PoP falls back to unavailable on iOS', () {
      final transport = selectBleOnboardingTransport(
        platform: TargetPlatform.iOS,
        developmentPop: '',
      );
      expect(transport, isA<NotImplementedBleOnboardingTransport>());
    });

    test('every other platform falls back to unavailable even with a '
        'configured PoP — only Android/iOS ever get a real transport', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        final transport = selectBleOnboardingTransport(
          platform: platform,
          developmentPop: 'dev-pop',
        );
        expect(
          transport,
          isA<NotImplementedBleOnboardingTransport>(),
          reason: '$platform must not get a real BLE transport',
        );
      }
    });
  });
}
