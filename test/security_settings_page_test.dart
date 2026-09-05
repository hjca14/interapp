import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:interapp/features/auth/presentation/pages/security_settings_page.dart';
import 'package:interapp/features/auth/presentation/providers/biometric_lock_providers.dart';
import 'package:interapp/features/devices/data/services/incoming_call_notification_service.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

void main() {
  Widget subject({
    required IncomingCallNotificationService notificationService,
  }) => ProviderScope(
    overrides: [
      biometricLockSettingsRepositoryProvider.overrideWithValue(
        _MemorySettingsRepository(),
      ),
      incomingCallNotificationServiceProvider.overrideWithValue(
        notificationService,
      ),
    ],
    child: const MaterialApp(home: SecuritySettingsPage()),
  );

  group('platform visibility of the full-screen call section', () {
    testWidgets(
      'Android keeps showing "Chamada em tela cheia" — same behavior as '
      'before this platform split',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final service = _RecordingNotificationService(
          checker: () async => true,
        );
        await tester.pumpWidget(subject(notificationService: service));
        await tester.pumpAndSettle();

        expect(find.text('Chamada em tela cheia'), findsOneWidget);
        // Must be cleared before the test body returns — flutter_test
        // verifies foundation debug variables are unset immediately after
        // the test body runs, before any addTearDown callback fires.
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('iOS never shows "Chamada em tela cheia" — it documents an '
        'Android-only special access (USE_FULL_SCREEN_INTENT) with no iOS '
        'counterpart, so it must not appear, not even disabled or reworded', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = _RecordingNotificationService(checker: () async => true);
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pumpAndSettle();

      expect(find.text('Chamada em tela cheia'), findsNothing);
      expect(find.text('Ativado'), findsNothing);
      expect(find.text('Não ativado'), findsNothing);
      expect(find.text('Abrir configuração do Android'), findsNothing);
      expect(
        service.requestCalls,
        0,
        reason: 'a hidden section must never touch the platform channel',
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets(
    'shows a loading indicator for the full-screen call section while '
    'the OS check is pending, never a button before it resolves',
    (tester) async {
      final service = _RecordingNotificationService(
        checker: () => Completer<bool>().future,
      );
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pump();

      expect(find.text('Chamada em tela cheia'), findsOneWidget);
      expect(find.text('Abrir configuração do Android'), findsNothing);
      expect(service.requestCalls, 0);
    },
  );

  testWidgets(
    'reports "Ativado" and offers no action when access is already granted',
    (tester) async {
      final service = _RecordingNotificationService(checker: () async => true);
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pumpAndSettle();

      expect(find.text('Ativado'), findsOneWidget);
      expect(find.text('Abrir configuração do Android'), findsNothing);
      expect(service.requestCalls, 0);
    },
  );

  testWidgets(
    'never requests full-screen access merely by opening the screen — only '
    'an explicit tap may trigger it',
    (tester) async {
      final service = _RecordingNotificationService(checker: () async => false);
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pumpAndSettle();

      expect(find.text('Não ativado'), findsOneWidget);
      expect(find.text('Abrir configuração do Android'), findsOneWidget);
      expect(service.requestCalls, 0);
    },
  );

  testWidgets('tapping the voluntary action requests access exactly once and '
      'refreshes the status shown', (tester) async {
    var granted = false;
    final service = _RecordingNotificationService(
      checker: () async => granted,
      onRequest: () => granted = true,
    );
    await tester.pumpWidget(subject(notificationService: service));
    await tester.pumpAndSettle();
    expect(find.text('Não ativado'), findsOneWidget);

    await tester.tap(find.text('Abrir configuração do Android'));
    await tester.pumpAndSettle();

    expect(service.requestCalls, 1);
    expect(find.text('Ativado'), findsOneWidget);
  });

  testWidgets(
    're-checks the real status on every app resume — never just trusts a '
    'value cached from before the user went to Android Settings',
    (tester) async {
      var checkCalls = 0;
      var granted = false;
      final service = _RecordingNotificationService(
        checker: () async {
          checkCalls++;
          return granted;
        },
      );
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pumpAndSettle();
      expect(find.text('Não ativado'), findsOneWidget);
      expect(checkCalls, 1);

      // Simulate the user backgrounding the app, granting access in Android
      // Settings, then coming straight back — never tapping the in-app
      // button (`requestFullScreenIntentAccess`, which already invalidates
      // on its own).
      granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(checkCalls, 2, reason: 'resume must trigger a fresh check');
      expect(find.text('Ativado'), findsOneWidget);
    },
  );

  testWidgets(
    're-checks the real status when the screen is re-entered, not a value '
    'cached from a previous visit',
    (tester) async {
      var checkCalls = 0;
      final service = _RecordingNotificationService(
        checker: () async {
          checkCalls++;
          return false;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricLockSettingsRepositoryProvider.overrideWithValue(
              _MemorySettingsRepository(),
            ),
            incomingCallNotificationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SecuritySettingsPage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(checkCalls, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        checkCalls,
        2,
        reason:
            're-entering the screen re-queries instead of reusing a '
            'stale cached result',
      );
    },
  );

  testWidgets(
    'a failed status check is reported without crashing, and never treated '
    'as granted',
    (tester) async {
      final service = _RecordingNotificationService(
        checker: () async => throw StateError('safe fake'),
      );
      await tester.pumpWidget(subject(notificationService: service));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível verificar.'), findsOneWidget);
      expect(find.text('Ativado'), findsNothing);
      expect(service.requestCalls, 0);
    },
  );
}

class _MemorySettingsRepository implements BiometricLockSettingsRepository {
  BiometricLockSettings settings = const BiometricLockSettings();

  @override
  Future<BiometricLockSettings> load() async => settings;

  @override
  Future<void> save(BiometricLockSettings value) async => settings = value;
}

/// Subclasses the real service (constructing it with a harmless, unused
/// plugin instance) so the injectable [checker] drives
/// `hasFullScreenIntentAccess`, while [requestFullScreenIntentAccess] is
/// overridden here instead of hitting a real platform channel — this test
/// only needs to prove the settings page never calls it except from an
/// explicit tap, and how many times it did.
class _RecordingNotificationService extends IncomingCallNotificationService {
  _RecordingNotificationService({
    required Future<bool> Function() checker,
    this.onRequest,
  }) : super(
         FlutterLocalNotificationsPlugin(),
         fullScreenIntentChecker: checker,
       );

  final void Function()? onRequest;
  int requestCalls = 0;

  @override
  Future<bool> requestFullScreenIntentAccess() async {
    requestCalls++;
    onRequest?.call();
    return true;
  }
}
