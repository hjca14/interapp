import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/local_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';
import 'package:interapp/features/pairing/presentation/pages/add_interbridge_page.dart';
import 'package:interapp/features/pairing/presentation/providers/pairing_providers.dart';

/// Never finds a device — the exact "no InterBridge nearby" scenario
/// confirmed on a physical Galaxy A12: `checkAvailability` reports no
/// issue, and the scan stream completes immediately without ever
/// discovering anything, so [OnboardingCoordinator]'s own 20s scan timeout
/// fires and produces the `scanTimeout` error step under test.
class _NoDeviceBleTransport implements BleOnboardingTransport {
  @override
  Future<BleAvailabilityIssue?> checkAvailability() async => null;

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() =>
      Stream.fromIterable(const []);

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String transportId) async {}

  @override
  Future<void> establishSecureSession() async {}

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Future<void> sendWifiCredentials(String ssid, String password) async {}

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {}

  @override
  Future<void> disconnect() async {}
}

/// Sets the test viewport's logical size (devicePixelRatio pinned to 1.0, so
/// [width]/[height] are directly the logical pixels every widget/constraint
/// sees) and the platform text scale, restoring all three after the test.
/// Mirrors the helper in
/// `test/notification_preferences_alert_mode_responsive_test.dart`.
void _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
  double textScaleFactor = 1.0,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _pumpToScanTimeoutError(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleOnboardingTransportProvider.overrideWithValue(
          _NoDeviceBleTransport(),
        ),
        onboardingClaimRepositoryProvider.overrideWithValue(
          LocalOnboardingClaimRepository(),
        ),
        onboardingAnalyticsProvider.overrideWithValue(
          DebugPrintOnboardingAnalytics(),
        ),
      ],
      child: const MaterialApp(home: AddInterBridgePage()),
    ),
  );
  await tester.pump();

  await tester.tap(find.text('Continuar'));
  await tester.pump();

  // OnboardingCoordinator's default scan timeout (20s) — a real dart:async
  // Timer, fast-forwarded by the test binding's fake clock, never a real
  // wait. See onboarding_coordinator.dart's `_scanTimeout`.
  await tester.pump(const Duration(seconds: 20));
  await tester.pump();
}

void main() {
  group('AddInterBridgePage — "no InterBridge nearby" error state layout '
      '(Galaxy A12 physical validation regression)', () {
    // (width, height, textScaleFactor, label). The second case reproduces a
    // real RenderFlex overflow against the pre-fix layout — see the PR
    // description for the diagnostic sweep that found it: a plain,
    // non-scrollable Column sized to `MainAxisAlignment.center` throws once
    // this step's six stacked elements (icon, title, body, primary button,
    // fallback links, cancel) exceed the viewport, which a bigger
    // accessibility text size alone is enough to trigger even on the exact
    // Galaxy A12 logical size (360×800 @ dpr 1.0 after normalizing to
    // logical pixels).
    const cases = [
      (width: 360.0, height: 800.0, scale: 1.0, label: 'Galaxy A12 baseline'),
      (
        width: 360.0,
        height: 800.0,
        scale: 1.6,
        label: 'Galaxy A12 at a larger accessibility text size',
      ),
      (
        width: 320.0,
        height: 640.0,
        scale: 1.0,
        label: 'a smaller/older phone or a reduced viewport',
      ),
    ];

    for (final c in cases) {
      testWidgets('${c.label} (${c.width.toInt()}x${c.height.toInt()}dp, scale '
          '${c.scale}): no overflow, and the icon, title, "Tentar novamente", '
          'fallback links and "Cancelar" all share the same horizontal '
          'center — no apparent left drift', (tester) async {
        _setViewport(
          tester,
          width: c.width,
          height: c.height,
          textScaleFactor: c.scale,
        );
        await _pumpToScanTimeoutError(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'the error step must never overflow on a narrow phone',
        );

        expect(
          find.text('Nenhum InterBridge encontrado por perto.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);
        expect(find.text('Escanear código QR'), findsOneWidget);
        expect(find.text('Digitar código manualmente'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);

        final screenCenterX = c.width / 2;
        final iconCenterX = tester
            .getCenter(find.byIcon(Icons.error_outline))
            .dx;
        final titleCenterX = tester
            .getCenter(find.text('Não foi possível continuar.'))
            .dx;
        final retryCenterX = tester
            .getCenter(find.widgetWithText(FilledButton, 'Tentar novamente'))
            .dx;
        final cancelCenterX = tester
            .getCenter(find.widgetWithText(TextButton, 'Cancelar'))
            .dx;

        for (final entry in {
          'icon': iconCenterX,
          'title': titleCenterX,
          'Tentar novamente button': retryCenterX,
          'Cancelar button': cancelCenterX,
        }.entries) {
          expect(
            entry.value,
            closeTo(screenCenterX, 1.0),
            reason:
                '${entry.key} must be centered on the screen\'s '
                'horizontal axis, not drifted left — got ${entry.value} '
                'vs. expected screen center $screenCenterX',
          );
        }
      });
    }
  });
}
