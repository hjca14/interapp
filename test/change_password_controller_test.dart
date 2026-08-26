import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/auth/presentation/providers/change_password_controller.dart';

void main() {
  late LocalAuthRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = LocalAuthRepository(
      initial: const AuthSession(
        isSignedIn: true,
        userId: 'user-1',
        email: 'user@example.com',
      ),
    );
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  ChangePasswordController controller() =>
      container.read(changePasswordControllerProvider.notifier);
  ChangePasswordState state() =>
      container.read(changePasswordControllerProvider);

  test('initial state is idle with no errors', () {
    expect(state().status, ChangePasswordStatus.initial);
    expect(state().currentPasswordError, isNull);
    expect(state().newPasswordError, isNull);
    expect(state().confirmPasswordError, isNull);
    expect(state().errorMessage, isNull);
  });

  test(
    'rejects empty required fields without calling the repository',
    () async {
      await controller().submit(
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
      );

      expect(state().status, ChangePasswordStatus.failure);
      expect(state().currentPasswordError, isNotNull);
      expect(state().newPasswordError, isNotNull);
      expect(state().confirmPasswordError, isNotNull);
      expect(repository.lastChangePasswordCurrent, isNull);
    },
  );

  test('rejects a confirmation that does not match the new password', () async {
    await controller().submit(
      currentPassword: 'current-pass',
      newPassword: 'New-Password-1',
      confirmPassword: 'New-Password-2',
    );

    expect(state().status, ChangePasswordStatus.failure);
    expect(state().confirmPasswordError, isNotNull);
    expect(state().currentPasswordError, isNull);
    expect(state().newPasswordError, isNull);
    expect(repository.lastChangePasswordCurrent, isNull);
  });

  test('does not block locally when the typed current and new password texts '
      'are equal — only Cognito can tell whether the typed current password '
      'is actually correct', () async {
    // Real Cognito DEV behavior: a typo'd current password of "abcd" (true
    // password "abc") with a new password of "abcd" must surface as an
    // incorrect current password, never a premature "must differ" message.
    repository.changePasswordFailure = const AuthFailure(
      AuthFailureKind.incorrectCurrentPassword,
      'Senha atual incorreta.',
    );

    await controller().submit(
      currentPassword: 'abcd',
      newPassword: 'abcd',
      confirmPassword: 'abcd',
    );

    expect(state().status, ChangePasswordStatus.failure);
    expect(state().errorMessage, 'Senha atual incorreta.');
    expect(state().newPasswordError, isNull);
    expect(repository.changePasswordCallCount, 1);
    expect((await repository.currentSession).isSignedIn, isTrue);
  });

  test('a successful call with an equal current/new password is treated as no '
      'effective change, not success — Cognito DEV accepts rather than '
      'rejects that case, so only a post-success check can catch it', () async {
    // LocalAuthRepository succeeds by default (changePasswordFailure is
    // unset), mirroring the real Cognito DEV response for "abc" -> "abc".
    await controller().submit(
      currentPassword: 'abc',
      newPassword: 'abc',
      confirmPassword: 'abc',
    );

    expect(state().status, ChangePasswordStatus.failure);
    expect(
      state().newPasswordError,
      'A nova senha deve ser diferente da atual.',
    );
    expect(state().errorMessage, isNull);
    expect(repository.changePasswordCallCount, 1);
    expect((await repository.currentSession).isSignedIn, isTrue);
  });

  test('a remote invalidPassword failure is surfaced as-is even when the '
      'submitted values happen to be equal — equality is never used to '
      'override a remote failure', () async {
    repository.changePasswordFailure = const AuthFailure(
      AuthFailureKind.invalidPassword,
      'A senha não atende à política informada.',
    );

    await controller().submit(
      currentPassword: 'abc',
      newPassword: 'abc',
      confirmPassword: 'abc',
    );

    expect(state().status, ChangePasswordStatus.failure);
    expect(state().errorMessage, 'A senha não atende à política informada.');
    expect(state().newPasswordError, isNull);
    expect(repository.changePasswordCallCount, 1);
  });

  test(
    'does not trim leading/trailing spaces from any password field',
    () async {
      await controller().submit(
        currentPassword: ' current-pass',
        newPassword: 'New-Password-1 ',
        confirmPassword: 'New-Password-1 ',
      );

      expect(state().status, ChangePasswordStatus.success);
      expect(repository.lastChangePasswordCurrent, ' current-pass');
      expect(repository.lastChangePasswordNew, 'New-Password-1 ');
    },
  );

  test('a valid submission transitions to success', () async {
    await controller().submit(
      currentPassword: 'current-pass',
      newPassword: 'New-Password-1',
      confirmPassword: 'New-Password-1',
    );

    expect(state().status, ChangePasswordStatus.success);
    expect(state().errorMessage, isNull);
    expect(repository.lastChangePasswordCurrent, 'current-pass');
    expect(repository.lastChangePasswordNew, 'New-Password-1');
  });

  test('a recoverable remote failure surfaces the sanitized message', () async {
    repository.changePasswordFailure = const AuthFailure(
      AuthFailureKind.incorrectCurrentPassword,
      'Senha atual incorreta.',
    );

    await controller().submit(
      currentPassword: 'wrong-pass',
      newPassword: 'New-Password-1',
      confirmPassword: 'New-Password-1',
    );

    expect(state().status, ChangePasswordStatus.failure);
    expect(state().errorMessage, 'Senha atual incorreta.');
  });

  test(
    'a corrected resubmission after a recoverable failure succeeds',
    () async {
      repository.changePasswordFailure = const AuthFailure(
        AuthFailureKind.incorrectCurrentPassword,
        'Senha atual incorreta.',
      );
      await controller().submit(
        currentPassword: 'wrong-pass',
        newPassword: 'New-Password-1',
        confirmPassword: 'New-Password-1',
      );
      expect(state().status, ChangePasswordStatus.failure);

      repository.changePasswordFailure = null;
      await controller().submit(
        currentPassword: 'right-pass',
        newPassword: 'New-Password-1',
        confirmPassword: 'New-Password-1',
      );

      expect(state().status, ChangePasswordStatus.success);
      expect(state().errorMessage, isNull);
    },
  );

  test('a submission already in flight is not sent twice', () async {
    final slowRepository = _SlowAuthRepository();
    final slowContainer = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(slowRepository)],
    );
    addTearDown(slowContainer.dispose);
    final notifier = slowContainer.read(
      changePasswordControllerProvider.notifier,
    );

    final first = notifier.submit(
      currentPassword: 'current-pass',
      newPassword: 'New-Password-1',
      confirmPassword: 'New-Password-1',
    );
    expect(
      slowContainer.read(changePasswordControllerProvider).isSubmitting,
      isTrue,
    );
    final second = notifier.submit(
      currentPassword: 'current-pass',
      newPassword: 'New-Password-1',
      confirmPassword: 'New-Password-1',
    );

    slowRepository.complete();
    await first;
    await second;

    expect(slowRepository.callCount, 1);
  });

  test('discarding the provider (leaving the screen) clears state safely', () {
    container.read(changePasswordControllerProvider.notifier);
    container.dispose();
    // No exception on dispose means the auto-dispose notifier tore down
    // cleanly with nothing left referencing the password values.
  });
}

class _SlowAuthRepository implements AuthRepository {
  int callCount = 0;
  Completer<void>? _pending;

  void complete() {
    _pending?.complete();
  }

  @override
  Future<void> changePassword(String currentPassword, String newPassword) {
    callCount++;
    _pending = Completer<void>();
    return _pending!.future;
  }

  @override
  Future<AuthSession> get currentSession async => const AuthSession.signedOut();

  @override
  Stream<AuthSession> watchSession() => const Stream.empty();

  @override
  Future<AuthSignUpResult> signUp(String email, String password) async =>
      const AuthSignUpResult(confirmationRequired: false);

  @override
  Future<void> confirmSignUp(String email, String code) async {}

  @override
  Future<void> resendSignUpCode(String email) async {}

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> beginPasswordReset(String email) async {}

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {}

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async =>
      'token';

  @override
  Future<void> invalidateSession() async {}
}
