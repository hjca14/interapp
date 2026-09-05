import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/local_onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';
import 'package:interapp/features/pairing/presentation/pages/add_interbridge_page.dart';
import 'package:interapp/features/pairing/presentation/providers/pairing_providers.dart';

const _device = DiscoveredInterBridge(
  transportId: 'ble-handle-a',
  friendlyName: 'InterBridge-AAAA',
);

/// Finds one physical InterBridge, connects, completes Security 1, then
/// drives whatever Wi-Fi provisioning outcome the test configures via
/// [wifiError]/[wifiFailureReason]/[wifiProgress] — mirrors
/// `_FakeBleTransport` in `onboarding_coordinator_test.dart`, but reused
/// here to drive the real widget tree instead of the coordinator directly.
class _ControllableBleTransport implements BleOnboardingTransport {
  Object? wifiError;
  WifiProvisioningFailureReason? wifiFailureReason;
  List<WifiProvisioningProgress> wifiProgress = const [
    WifiProvisioningProgress.sendingConfig,
    WifiProvisioningProgress.applyingConfig,
  ];
  int disconnectCallCount = 0;
  final wifiCallArguments = <(String ssid, String password)>[];

  /// When non-empty, `sendWifiCredentials` awaits `wifiGates.removeAt(0)`
  /// before each yield/failure — one gate per step a test wants to pause
  /// at, so the transient "sending"/"applying" progress UI is observable
  /// instead of a zero-delay fake resolving the whole flow within one pump.
  final wifiGates = <Completer<void>>[];

  @override
  Future<BleAvailabilityIssue?> checkAvailability() async => null;

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() async* {
    yield _device;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String transportId) async {}

  @override
  Future<void> establishSecureSession() async {}

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Stream<WifiProvisioningProgress> sendWifiCredentials(
    String ssid,
    String password,
  ) async* {
    wifiCallArguments.add((ssid, password));
    if (wifiError != null) {
      throw wifiError!;
    }
    for (final step in wifiProgress) {
      yield step;
      // One gate per step lets a test pause right after that step is
      // yielded — otherwise the next step's (or the stream's closing)
      // state change coalesces into the same widget frame, since Flutter
      // only renders once per pump regardless of how many state changes
      // happened before it.
      if (wifiGates.isNotEmpty) {
        await wifiGates.removeAt(0).future;
      }
    }
    if (wifiFailureReason != null) {
      throw WifiProvisioningException(wifiFailureReason!);
    }
  }

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {}

  @override
  Future<void> disconnect() async => disconnectCallCount++;
}

Future<void> _pumpToWifiForm(
  WidgetTester tester,
  _ControllableBleTransport ble,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleOnboardingTransportProvider.overrideWithValue(ble),
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
  await tester.pump(); // checkingSetupMode -> scanningBle
  await tester.pump(); // device discovered -> deviceFound

  await tester.tap(find.text(_device.friendlyName));
  await tester.pump();
  await tester.tap(find.text('Sim, continuar'));
  // Cancelling the still-pending 20s real scanTimeout Timer (created by
  // OnboardingCoordinator, not overridable from AddInterBridgePage) takes
  // many fake-clock pump steps to fully settle — runAsync flushes it via
  // the real event loop instead of pump-spamming.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump();

  expect(find.text('Conectar à internet'), findsOneWidget);
}

/// Sets the test viewport's logical size (devicePixelRatio pinned to 1.0),
/// restoring it after the test. Mirrors the helper in
/// `test/add_interbridge_error_state_layout_test.dart`.
void _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _submitWifiForm(
  WidgetTester tester, {
  String ssid = 'home-network',
  String password = 'wifi-password',
}) async {
  await tester.enterText(find.byType(TextField).at(0), ssid);
  await tester.enterText(find.byType(TextField).at(1), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
  await tester.pump();
}

void main() {
  testWidgets('the device confirmation step names the selected device without '
      'repeating the "found nearby" framing already shown on the previous '
      'screen, and keeps both actions available', (tester) async {
    final ble = _ControllableBleTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleOnboardingTransportProvider.overrideWithValue(ble),
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
    await tester.pump(); // checkingSetupMode -> scanningBle
    await tester.pump(); // device discovered -> deviceFound

    await tester.tap(find.text(_device.friendlyName));
    await tester.pump();

    expect(find.text('InterBridge selecionado'), findsOneWidget);
    expect(find.text(_device.friendlyName), findsOneWidget);
    expect(
      find.textContaining('Confirme se a luz dele está piscando'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Encontramos'),
      findsNothing,
      reason:
          'the previous (device list) screen already said a device was '
          'found — this one must not repeat that framing',
    );
    expect(find.text('Sim, continuar'), findsOneWidget);
    expect(find.text('Não é este'), findsOneWidget);
  });

  testWidgets(
    'a successful Wi-Fi connection shows an honest confirmation — never '
    '"sucesso"/"configurado com sucesso", never added to a device list, '
    'and clearly states registration is a next step',
    (tester) async {
      final ble = _ControllableBleTransport();
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Wi-Fi configurado.'), findsOneWidget);
      expect(
        find.textContaining('próxima etapa'),
        findsOneWidget,
        reason: 'registration/activation must be framed as a next step',
      );
      expect(
        find.textContaining('sucesso'),
        findsNothing,
        reason: 'Wi-Fi connecting is never framed as onboarding success',
      );
      expect(
        find.textContaining('lista de dispositivos'),
        findsNothing,
        reason: 'the device must never be presented as added to the list',
      );
      expect(ble.wifiCallArguments, [('home-network', 'wifi-password')]);
      expect(
        ble.disconnectCallCount,
        1,
        reason: 'the BLE session is released once its job is done',
      );

      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'shows "sending" then "connecting" progress messages while the device '
    'applies the Wi-Fi config, before the honest confirmation',
    (tester) async {
      final ble = _ControllableBleTransport();
      final afterSending = Completer<void>();
      final afterApplying = Completer<void>();
      ble.wifiGates.addAll([afterSending, afterApplying]);
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester);
      await tester.pump();
      expect(
        find.text('Enviando rede Wi‑Fi...'),
        findsOneWidget,
        reason: 'sending is shown immediately, before the device replies',
      );

      // Unblocks the "sendingConfig" step the generator already yielded,
      // letting it proceed to yield "applyingConfig" — then it pauses
      // again (afterApplying), so this next state is observable on its own.
      afterSending.complete();
      await tester.pump();
      expect(
        find.text('Conectando o InterBridge à rede Wi-Fi...'),
        findsOneWidget,
      );

      afterApplying.complete();
      await tester.pump();
      expect(find.text('Wi-Fi configurado.'), findsOneWidget);
    },
  );

  testWidgets(
    'the "sending Wi-Fi" progress message renders without overflowing on a '
    'Galaxy A12-width screen, using a non-breaking hyphen in "Wi‑Fi" so '
    'the browser/engine line-breaker never splits it mid-word the way the '
    'old, longer copy with a plain hyphen did',
    (tester) async {
      _setViewport(tester, width: 360.0, height: 800.0);
      final ble = _ControllableBleTransport()..wifiGates.add(Completer<void>());
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester);
      await tester.pump();

      const message = 'Enviando rede Wi‑Fi...';
      expect(find.text(message), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the sending step must never overflow on a narrow phone',
      );
      expect(
        message.contains('Wi-Fi'),
        isFalse,
        reason:
            'must use a non-breaking hyphen (U+2011) in "Wi‑Fi", not a '
            'plain one — a plain hyphen is exactly what let the layout '
            'engine break the line between "Wi-" and "Fi" before',
      );
    },
  );

  testWidgets(
    'an empty password is accepted for an open network — only SSID is '
    'required',
    (tester) async {
      final ble = _ControllableBleTransport();
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester, password: '');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Wi-Fi configurado.'), findsOneWidget);
      expect(ble.wifiCallArguments, [('home-network', '')]);
    },
  );

  testWidgets(
    'an empty SSID never submits — the form stays on the Wi-Fi step',
    (tester) async {
      final ble = _ControllableBleTransport();
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester, ssid: '');
      await tester.pump();

      expect(find.text('Conectar à internet'), findsOneWidget);
      expect(ble.wifiCallArguments, isEmpty);
    },
  );

  testWidgets(
    'a wrong-password failure shows a specific message and offers retry, '
    'never a generic "success"',
    (tester) async {
      final ble = _ControllableBleTransport()
        ..wifiFailureReason = WifiProvisioningFailureReason.authFailed;
      await _pumpToWifiForm(tester, ble);

      await _submitWifiForm(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Senha'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('Wi-Fi configurado.'), findsNothing);
      expect(
        ble.disconnectCallCount,
        1,
        reason: 'a failed attempt still releases the BLE connection',
      );
    },
  );

  testWidgets(
    'retrying after a Wi-Fi failure re-discovers the device instead of '
    'reusing the stale connection',
    (tester) async {
      final ble = _ControllableBleTransport()
        ..wifiFailureReason = WifiProvisioningFailureReason.networkNotFound;
      await _pumpToWifiForm(tester, ble);
      await _submitWifiForm(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Tentar novamente'), findsOneWidget);

      ble.wifiFailureReason = null;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        find.text(_device.friendlyName),
        findsOneWidget,
        reason: 'retry re-scans and finds the device again',
      );
    },
  );
}
