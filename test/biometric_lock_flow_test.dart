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
  var now = DateTime(2026);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        biometricLockSettingsRepositoryProvider.overrideWithValue(
          _MemorySettingsRepository(
            const BiometricLockSettings(
              enabled: true,
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

class _FakeBiometrics implements BiometricAuthenticator {
  _FakeBiometrics({
    this.configuredAvailability = BiometricAvailability.available,
    this.result = BiometricAuthenticationResult.success,
  });

  final BiometricAvailability configuredAvailability;
  final BiometricAuthenticationResult result;
  int authenticateCalls = 0;

  @override
  Future<BiometricAvailability> availability() async => configuredAvailability;

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    authenticateCalls++;
    return result;
  }
}
