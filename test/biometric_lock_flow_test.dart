import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_call_navigation.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/auth/presentation/providers/biometric_lock_providers.dart';
import 'package:interapp/features/auth/presentation/widgets/biometric_lock_gate.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

void main() {
  group('biometric lock activation', () {
    test(
      'enrolled biometric is confirmed before enablement is persisted',
      () async {
        final repository = _MemorySettingsRepository();
        final biometrics = _FakeBiometrics(
          result: BiometricAuthenticationResult.success,
        );
        final container = _container(repository, biometrics);
        addTearDown(container.dispose);

        await container.read(biometricLockSettingsProvider.future);
        await container
            .read(biometricLockSettingsProvider.notifier)
            .setEnabled(true);

        expect(biometrics.authenticateCalls, 1);
        expect(repository.settings.enabled, isTrue);
      },
    );

    test('canceling confirmation never persists enablement', () async {
      final repository = _MemorySettingsRepository();
      final container = _container(
        repository,
        _FakeBiometrics(result: BiometricAuthenticationResult.canceled),
      );
      addTearDown(container.dispose);
      await container.read(biometricLockSettingsProvider.future);

      await expectLater(
        container.read(biometricLockSettingsProvider.notifier).setEnabled(true),
        throwsA(
          isA<BiometricActivationException>().having(
            (error) => error.result,
            'result',
            BiometricAuthenticationResult.canceled,
          ),
        ),
      );
      expect(repository.settings.enabled, isFalse);
      expect(repository.saveCalls, 0);
    });

    for (final availability in [
      BiometricAvailability.notEnrolled,
      BiometricAvailability.unsupported,
    ]) {
      test('$availability never enables the setting', () async {
        final repository = _MemorySettingsRepository();
        final biometrics = _FakeBiometrics(
          configuredAvailability: availability,
        );
        final container = _container(repository, biometrics);
        addTearDown(container.dispose);
        await container.read(biometricLockSettingsProvider.future);

        await expectLater(
          container
              .read(biometricLockSettingsProvider.notifier)
              .setEnabled(true),
          throwsA(isA<BiometricActivationException>()),
        );
        expect(repository.settings.enabled, isFalse);
        expect(biometrics.authenticateCalls, 0);
      });
    }

    test(
      'a device credential such as PIN or pattern is not biometric',
      () async {
        final repository = _MemorySettingsRepository();
        final biometrics = _FakeBiometrics(
          configuredAvailability: BiometricAvailability.notEnrolled,
        );
        final container = _container(repository, biometrics);
        addTearDown(container.dispose);
        await container.read(biometricLockSettingsProvider.future);

        await expectLater(
          container
              .read(biometricLockSettingsProvider.notifier)
              .setEnabled(true),
          throwsA(isA<BiometricActivationException>()),
        );
        expect(repository.settings.enabled, isFalse);
        expect(biometrics.authenticateCalls, 0);
      },
    );
  });

  group('locked gate', () {
    testWidgets('cold start blocks before protected content is shown', (
      tester,
    ) async {
      await _pumpGate(
        tester,
        biometrics: _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        ),
      );

      expect(find.text('Conteúdo protegido'), findsNothing);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
    });

    testWidgets('locked texts inherit the normal Material text style', (
      tester,
    ) async {
      await _pumpGate(
        tester,
        biometrics: _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        ),
      );

      final context = tester.element(
        find.text('Confirme sua biometria para acessar o InterBridge.'),
      );
      final inheritedStyle = DefaultTextStyle.of(context).style;
      final materialStyle = Theme.of(context).textTheme.bodyMedium!;

      expect(find.byType(Scaffold), findsOneWidget);
      expect(inheritedStyle.color, materialStyle.color);
      expect(inheritedStyle.fontFamily, materialStyle.fontFamily);
      expect(inheritedStyle.decoration, materialStyle.decoration);
      expect(inheritedStyle.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('cold start opens exactly one prompt', (tester) async {
      final biometrics = _FakeBiometrics(
        result: BiometricAuthenticationResult.canceled,
      );
      await _pumpGate(tester, biometrics: biometrics);

      expect(biometrics.authenticateCalls, 1);
      await tester.pump();
      expect(biometrics.authenticateCalls, 1);
    });

    testWidgets('native prompt lifecycle events do not duplicate cold prompt', (
      tester,
    ) async {
      final authentication = Completer<BiometricAuthenticationResult>();
      final biometrics = _FakeBiometrics(authentication: authentication);
      await _pumpGate(tester, biometrics: biometrics, settle: false);

      expect(biometrics.authenticateCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      authentication.complete(BiometricAuthenticationResult.canceled);
      await tester.pump();

      expect(biometrics.authenticateCalls, 1);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
    });

    testWidgets('disabled cold start shows protected content normally', (
      tester,
    ) async {
      final biometrics = _FakeBiometrics();
      await _pumpGate(tester, biometrics: biometrics, enabled: false);

      expect(find.text('Conteúdo protegido'), findsOneWidget);
      expect(biometrics.authenticateCalls, 0);
    });

    testWidgets('loading preferences never flashes protected content', (
      tester,
    ) async {
      final repository = _DeferredSettingsRepository();
      await _pumpGate(
        tester,
        biometrics: _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        ),
        repository: repository,
        settle: false,
      );

      expect(find.text('Conteúdo protegido'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.complete(const BiometricLockSettings(enabled: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Conteúdo protegido'), findsNothing);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
    });

    testWidgets('successful cold-start authentication releases content', (
      tester,
    ) async {
      await _pumpGate(tester, biometrics: _FakeBiometrics());

      expect(find.text('Conteúdo protegido'), findsOneWidget);
      expect(find.text('Desbloqueie para continuar'), findsNothing);
    });

    testWidgets('automatic prompt occurs once and cancel keeps gate locked', (
      tester,
    ) async {
      final biometrics = _FakeBiometrics(
        result: BiometricAuthenticationResult.canceled,
      );
      await _pumpLockedGate(tester, biometrics: biometrics);

      expect(biometrics.authenticateCalls, 1);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
      await tester.pump();
      expect(biometrics.authenticateCalls, 1);
    });

    testWidgets('background and resume still locks after cold-start unlock', (
      tester,
    ) async {
      final biometrics = _FakeBiometrics(
        results: [
          BiometricAuthenticationResult.success,
          BiometricAuthenticationResult.canceled,
        ],
      );
      await _pumpGate(tester, biometrics: biometrics, simulateBackground: true);

      expect(biometrics.authenticateCalls, 2);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
      expect(find.text('Conteúdo protegido'), findsNothing);
    });

    testWidgets('unlock button starts another biometric attempt', (
      tester,
    ) async {
      final biometrics = _FakeBiometrics(
        result: BiometricAuthenticationResult.canceled,
      );
      await _pumpLockedGate(tester, biometrics: biometrics);

      await tester.tap(find.text('Desbloquear'));
      await tester.pump();
      expect(biometrics.authenticateCalls, 2);
    });

    testWidgets('email fallback signs out', (tester) async {
      final auth = LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true, userId: 'user'),
      );
      await _pumpLockedGate(
        tester,
        auth: auth,
        biometrics: _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        ),
      );

      await tester.tap(find.text('Entrar com e-mail e senha'));
      await tester.pump();
      expect((await auth.currentSession).isSignedIn, isFalse);
    });

    testWidgets(
      'never opens an automatic prompt while a call is pending/active, '
      'and opens exactly one once the call ends — never two stacked '
      'prompts (before showing the call, and again on dismiss)',
      (tester) async {
        final biometrics = _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        );
        final callIntent = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);
        coordinator.acceptSerialized(callIntent.serialize());
        expect(coordinator.hasPending, isTrue);

        await _pumpGate(
          tester,
          biometrics: biometrics,
          ringCallCoordinator: coordinator,
        );

        expect(
          biometrics.authenticateCalls,
          0,
          reason: 'no prompt while the call is still pending/active',
        );
        expect(find.text('Conteúdo protegido'), findsOneWidget);
        expect(find.text('Desbloqueie para continuar'), findsNothing);

        coordinator.endCall(callIntent.callId);
        await tester.pump();
        await tester.pump();

        expect(
          biometrics.authenticateCalls,
          1,
          reason: 'the deferred prompt now runs exactly once',
        );
        expect(
          find.text('Desbloqueie para continuar'),
          findsOneWidget,
          reason:
              'cold start into a pending call must never release the '
              'rest of the app once the call ends — the deferred prompt '
              'was canceled, so the gate stays locked',
        );
        expect(find.text('Conteúdo protegido'), findsNothing);
        coordinator.dispose();
      },
    );

    /// A call's own presentation (notification shade, a tap, full-screen
    /// intent, `MainActivity` toggling `showWhenLocked`, the system prompt
    /// over it, returning from the call screen) can itself emit transient
    /// inactive/paused/resumed lifecycle events with no real backgrounding
    /// by the user at all — these four tests are the direct regression
    /// coverage for that bug: an app the user was already using **unlocked**
    /// must reveal the exact same content, still unlocked, once the call
    /// ends via each of the ways a call can end. `IncomingCallPage._answer`/
    /// `_dismiss` both call the same `RingCallNavigationCoordinator.endCall`
    /// (see incoming_call_page.dart), and `IncomingCallNotificationService`
    /// routes a remote `RING_ENDED` and the coordinator's own internal
    /// ring-timeout through that identical call too — so from this gate's
    /// perspective, Atender/Dispensar/RING_ENDED/timeout are the same
    /// signal, already exhaustively covered as such; the coordinator's own
    /// ring-timeout *timer* mechanics are covered separately in
    /// ring_call_navigation_test.dart.
    for (final endReason in ['Dispensar', 'Atender', 'RING_ENDED', 'timeout']) {
      testWidgets('already unlocked in foreground: a call interrupted by a '
          'notification-shade-like lifecycle blip, then ended via $endReason, '
          'reveals the exact same content — still unlocked, no new prompt', (
        tester,
      ) async {
        final biometrics = _FakeBiometrics();
        final callIntent = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);

        await _pumpGate(
          tester,
          biometrics: biometrics,
          ringCallCoordinator: coordinator,
        );
        expect(
          find.text('Conteúdo protegido'),
          findsOneWidget,
          reason: 'setup: the app must start unlocked, in foreground',
        );
        expect(biometrics.authenticateCalls, 1);

        coordinator.acceptSerialized(callIntent.serialize());
        await tester.pump();

        // The notification shade opening/closing around the tap — an
        // ordinary AppLifecycleState cycle with a call already in flight.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(
          find.text('Conteúdo protegido'),
          findsOneWidget,
          reason: 'still unlocked while the call is in flight',
        );
        expect(biometrics.authenticateCalls, 1);

        coordinator.endCall(callIntent.callId);
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Conteúdo protegido'),
          findsOneWidget,
          reason:
              '$endReason must reveal the exact prior content, still '
              'unlocked',
        );
        expect(find.text('Desbloqueie para continuar'), findsNothing);
        expect(
          biometrics.authenticateCalls,
          1,
          reason: 'no new biometric prompt was started',
        );
        coordinator.dispose();
      });
    }

    testWidgets(
      'multiple lifecycle blips during one call never accumulate into a '
      'lock — each is independently classified by whether a call is '
      'actually in flight at that resume',
      (tester) async {
        final biometrics = _FakeBiometrics();
        final callIntent = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);

        await _pumpGate(
          tester,
          biometrics: biometrics,
          ringCallCoordinator: coordinator,
        );
        coordinator.acceptSerialized(callIntent.serialize());
        await tester.pump();

        for (var i = 0; i < 3; i++) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        }

        coordinator.endCall(callIntent.callId);
        await tester.pump();
        await tester.pump();

        expect(find.text('Conteúdo protegido'), findsOneWidget);
        expect(biometrics.authenticateCalls, 1);
        coordinator.dispose();
      },
    );

    testWidgets(
      'ending an unrelated call_id never affects the gate\'s state for the '
      'call actually in flight',
      (tester) async {
        final biometrics = _FakeBiometrics();
        final activeCall = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);

        await _pumpGate(
          tester,
          biometrics: biometrics,
          ringCallCoordinator: coordinator,
        );
        coordinator.acceptSerialized(activeCall.serialize());
        await tester.pump();

        // A RING_ENDED for a call this gate/coordinator never held.
        coordinator.endCall('call-${List.filled(32, 'd').join()}');
        await tester.pump();

        expect(
          coordinator.hasPending || coordinator.shouldOpen,
          isTrue,
          reason: 'the unrelated end must not have touched the real call',
        );
        expect(find.text('Conteúdo protegido'), findsOneWidget);
        expect(biometrics.authenticateCalls, 1);

        coordinator.endCall(activeCall.callId);
        await tester.pump();
        await tester.pump();

        expect(find.text('Conteúdo protegido'), findsOneWidget);
        expect(biometrics.authenticateCalls, 1);
        coordinator.dispose();
      },
    );

    testWidgets(
      'already locked before an unrelated call arrives stays locked after '
      'it ends — a call never grants local authentication',
      (tester) async {
        final biometrics = _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);

        // Cold start locked (biometrics canceled — matches "locked gate"
        // group's own default fixture), with no call at all yet.
        await _pumpLockedGate(tester, biometrics: biometrics);
        expect(find.text('Desbloqueie para continuar'), findsOneWidget);
        expect(biometrics.authenticateCalls, 1);

        final callIntent = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        coordinator.acceptSerialized(callIntent.serialize());
        coordinator.endCall(callIntent.callId);
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Desbloqueie para continuar'),
          findsOneWidget,
          reason:
              'a call arriving and ending never unlocks an already-'
              'locked gate',
        );
        expect(find.text('Conteúdo protegido'), findsNothing);
        coordinator.dispose();
      },
    );

    testWidgets(
      'the suppression during a call leaves no lingering bypass — a later, '
      'genuinely unrelated backgrounding still locks normally',
      (tester) async {
        final biometrics = _FakeBiometrics();
        final callIntent = RingCallIntent(
          eventId: 'evt-${List.filled(32, 'a').join()}',
          callId: 'call-${List.filled(32, 'c').join()}',
          deviceId: 'ib-${List.filled(32, 'b').join()}',
          occurredAt: DateTime(2026),
        );
        final coordinator = RingCallNavigationCoordinator(
          (_) async => true,
          now: () => DateTime(2026),
        );
        coordinator.setAuthenticated(true);

        await _pumpGate(
          tester,
          biometrics: biometrics,
          ringCallCoordinator: coordinator,
        );
        coordinator.acceptSerialized(callIntent.serialize());
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        coordinator.endCall(callIntent.callId);
        await tester.pump();
        await tester.pump();
        expect(find.text('Conteúdo protegido'), findsOneWidget);

        // A later, genuinely unrelated backgrounding — no call involved.
        // biometrics defaults to success, so the automatic re-attempt this
        // triggers immediately unlocks again — the point here is that a new
        // attempt is triggered at all (proving the lock *evaluation* ran,
        // not suppressed by a lingering exception), not that the lock
        // screen stays visible.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump();

        expect(
          biometrics.authenticateCalls,
          2,
          reason:
              'the exception was scoped to that one call, not a '
              'standing bypass — a real backgrounding afterward is '
              'evaluated normally and triggers a fresh attempt',
        );
        coordinator.dispose();
      },
    );

    testWidgets('large text scale does not overflow', (tester) async {
      await _pumpLockedGate(
        tester,
        textScaler: const TextScaler.linear(2.5),
        biometrics: _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Confirme sua biometria para acessar o InterBridge.'),
        findsOneWidget,
      );
    });
  });
}

ProviderContainer _container(
  _MemorySettingsRepository repository,
  _FakeBiometrics biometrics,
) => ProviderContainer(
  overrides: [
    biometricLockSettingsRepositoryProvider.overrideWithValue(repository),
    biometricAuthenticatorProvider.overrideWithValue(biometrics),
  ],
);

Future<void> _pumpLockedGate(
  WidgetTester tester, {
  required _FakeBiometrics biometrics,
  LocalAuthRepository? auth,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await _pumpGate(
    tester,
    biometrics: biometrics,
    auth: auth,
    textScaler: textScaler,
  );
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required _FakeBiometrics biometrics,
  LocalAuthRepository? auth,
  TextScaler textScaler = TextScaler.noScaling,
  bool enabled = true,
  bool simulateBackground = false,
  bool settle = true,
  BiometricLockSettingsRepository? repository,
  RingCallNavigationCoordinator? ringCallCoordinator,
}) async {
  var now = DateTime(2026);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        biometricLockSettingsRepositoryProvider.overrideWithValue(
          repository ??
              _MemorySettingsRepository(
                BiometricLockSettings(
                  enabled: enabled,
                  backgroundTimeout: Duration.zero,
                ),
              ),
        ),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        authRepositoryProvider.overrideWithValue(
          auth ??
              LocalAuthRepository(
                initial: const AuthSession(isSignedIn: true, userId: 'user'),
              ),
        ),
        if (ringCallCoordinator != null)
          ringCallNavigationCoordinatorProvider.overrideWithValue(
            ringCallCoordinator,
          ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: BiometricLockGate(
          now: () => now,
          child: const Scaffold(body: Text('Conteúdo protegido')),
        ),
      ),
    ),
  );
  await tester.pump();
  if (settle) {
    await tester.pump();
  }
  if (!simulateBackground) {
    return;
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  now = now.add(const Duration(seconds: 1));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump();
}

class _MemorySettingsRepository implements BiometricLockSettingsRepository {
  _MemorySettingsRepository([this.settings = const BiometricLockSettings()]);

  BiometricLockSettings settings;
  int saveCalls = 0;

  @override
  Future<BiometricLockSettings> load() async => settings;

  @override
  Future<void> save(BiometricLockSettings value) async {
    saveCalls++;
    settings = value;
  }
}

class _DeferredSettingsRepository implements BiometricLockSettingsRepository {
  final _completer = Completer<BiometricLockSettings>();

  void complete(BiometricLockSettings settings) =>
      _completer.complete(settings);

  @override
  Future<BiometricLockSettings> load() => _completer.future;

  @override
  Future<void> save(BiometricLockSettings settings) async {}
}

class _FakeBiometrics implements BiometricAuthenticator {
  _FakeBiometrics({
    this.configuredAvailability = BiometricAvailability.available,
    this.result = BiometricAuthenticationResult.success,
    this.results,
    this.authentication,
  });

  final BiometricAvailability configuredAvailability;
  final BiometricAuthenticationResult result;
  final List<BiometricAuthenticationResult>? results;
  final Completer<BiometricAuthenticationResult>? authentication;
  int authenticateCalls = 0;

  @override
  Future<BiometricAvailability> availability() async => configuredAvailability;

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    authenticateCalls++;
    final pendingAuthentication = authentication;
    if (pendingAuthentication != null) {
      return pendingAuthentication.future;
    }
    final authenticationResults = results;
    return authenticationResults == null
        ? result
        : authenticationResults[authenticateCalls - 1];
  }
}
