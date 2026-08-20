import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/auth/presentation/providers/biometric_lock_providers.dart';
import 'package:interapp/features/auth/presentation/widgets/biometric_lock_gate.dart';

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
        container
            .read(biometricLockSettingsProvider.notifier)
            .setEnabled(true),
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

    test('a device credential such as PIN or pattern is not biometric', () async {
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
    });
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
      await _pumpGate(
        tester,
        biometrics: biometrics,
        settle: false,
      );

      expect(biometrics.authenticateCalls, 1);
      await tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      authentication.complete(BiometricAuthenticationResult.canceled);
      await tester.pump();
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

      repository.complete(
        const BiometricLockSettings(enabled: true),
      );
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
      await _pumpGate(
        tester,
        biometrics: biometrics,
        simulateBackground: true,
      );

      expect(biometrics.authenticateCalls, 2);
      expect(find.text('Desbloqueie para continuar'), findsOneWidget);
      expect(find.text('Conteúdo protegido'), findsNothing);
    });

    testWidgets(
      'unlock button starts another biometric attempt',
      (tester) async {
        final biometrics = _FakeBiometrics(
          result: BiometricAuthenticationResult.canceled,
        );
        await _pumpLockedGate(tester, biometrics: biometrics);

        await tester.tap(find.text('Desbloquear'));
        await tester.pump();
        expect(biometrics.authenticateCalls, 2);
      },
    );

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
                initial: const AuthSession(
                  isSignedIn: true,
                  userId: 'user',
                ),
              ),
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
  await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  now = now.add(const Duration(seconds: 1));
  await tester.binding.handleAppLifecycleStateChanged(
    AppLifecycleState.resumed,
  );
  await tester.pump();
  await tester.pump();
}

class _MemorySettingsRepository implements BiometricLockSettingsRepository {
  _MemorySettingsRepository([
    this.settings = const BiometricLockSettings(),
  ]);

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

  void complete(BiometricLockSettings settings) => _completer.complete(settings);

  @override
  Future<BiometricLockSettings> load() => _completer.future;

  @override
  Future<void> save(BiometricLockSettings settings) async {}
}

class _FakeBiometrics implements BiometricAuthenticator {
  _FakeBiometrics({
    this.configuredAvailability = BiometricAvailability.available,
    this.result = BiometricAuthenticationResult.success,
    List<BiometricAuthenticationResult>? results,
    Completer<BiometricAuthenticationResult>? authentication,
  }) : _results = results,
       _authentication = authentication;

  final BiometricAvailability configuredAvailability;
  final BiometricAuthenticationResult result;
  final List<BiometricAuthenticationResult>? _results;
  final Completer<BiometricAuthenticationResult>? _authentication;
  int authenticateCalls = 0;

  @override
  Future<BiometricAvailability> availability() async => configuredAvailability;

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    authenticateCalls++;
    final authentication = _authentication;
    if (authentication != null) {
      return authentication.future;
    }
    final results = _results;
    return results == null ? result : results[authenticateCalls - 1];
  }
}
