import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/cognito_auth_repository.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

class _FakeGateway implements CognitoAuthGateway {
  Object? updatePasswordError;
  bool signOutCalled = false;
  String? capturedOldPassword;
  String? capturedNewPassword;
  int updatePasswordCallCount = 0;
  int sessionCheckCallCount = 0;

  /// What [hasValidSessionAfterForceRefresh] resolves to when no
  /// [sessionCheckError] is set. Defaults to the fail-closed value so a test
  /// that forgets to configure it never accidentally looks "valid".
  bool sessionCheckResult = false;
  Object? sessionCheckError;

  @override
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    updatePasswordCallCount++;
    capturedOldPassword = oldPassword;
    capturedNewPassword = newPassword;
    final error = updatePasswordError;
    if (error != null) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<bool> hasValidSessionAfterForceRefresh() async {
    sessionCheckCallCount++;
    final error = sessionCheckError;
    if (error != null) {
      // ignore: only_throw_errors
      throw error;
    }
    return sessionCheckResult;
  }

  @override
  Future<ResetPasswordResult> resetPassword({required String username}) {
    throw UnimplementedError('not exercised by this test file');
  }

  @override
  Future<void> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) {
    throw UnimplementedError('not exercised by this test file');
  }
}

void main() {
  const currentPassword = 's3cr3t-current!';
  const newPassword = 'Br4nd-N3w-P4ss!';

  late _FakeGateway gateway;
  late CognitoAuthRepository repository;

  setUp(() {
    gateway = _FakeGateway();
    repository = CognitoAuthRepository(authGateway: gateway);
  });

  test('forwards the current and new password unchanged to Amplify', () async {
    await repository.changePassword(currentPassword, newPassword);

    expect(gateway.capturedOldPassword, currentPassword);
    expect(gateway.capturedNewPassword, newPassword);
  });

  test('does not throw on success', () async {
    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      completes,
    );
  });

  group('NotAuthorizedException disambiguation (never by message text)', () {
    test(
      'an arbitrary message with no "incorrect" wording and a session that '
      'is still valid after forced refresh resolves to incorrectCurrentPassword',
      () async {
        gateway.updatePasswordError = const NotAuthorizedServiceException(
          'zzz some unrelated wording the SDK could ever return zzz',
        );
        gateway.sessionCheckResult = true;

        await expectLater(
          repository.changePassword(currentPassword, newPassword),
          throwsA(
            isA<AuthFailure>().having(
              (failure) => failure.kind,
              'kind',
              AuthFailureKind.incorrectCurrentPassword,
            ),
          ),
        );
        expect(gateway.signOutCalled, isFalse);
      },
    );

    test(
      'a message containing "incorrect" but an invalid session after forced '
      'refresh still resolves to sessionExpired — message text is ignored',
      () async {
        gateway.updatePasswordError = const NotAuthorizedServiceException(
          'Incorrect username or password.',
        );
        gateway.sessionCheckResult = false;

        await expectLater(
          repository.changePassword(currentPassword, newPassword),
          throwsA(
            isA<AuthFailure>().having(
              (failure) => failure.kind,
              'kind',
              AuthFailureKind.sessionExpired,
            ),
          ),
        );
        expect(gateway.signOutCalled, isTrue);
      },
    );

    test('a valid session is never invalidated', () async {
      gateway.updatePasswordError = const NotAuthorizedServiceException(
        'irrelevant',
      );
      gateway.sessionCheckResult = true;

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(isA<AuthFailure>()),
      );

      expect(gateway.signOutCalled, isFalse);
    });

    test('an invalid session is invalidated centrally', () async {
      gateway.updatePasswordError = const NotAuthorizedServiceException(
        'irrelevant',
      );
      gateway.sessionCheckResult = false;

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(isA<AuthFailure>()),
      );

      expect(gateway.signOutCalled, isTrue);
    });

    test('a failure while checking the session itself fails closed as '
        'sessionExpired instead of leaking the check failure', () async {
      gateway.updatePasswordError = const NotAuthorizedServiceException(
        'irrelevant',
      );
      gateway.sessionCheckError = const NetworkException('refresh unreachable');

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.sessionExpired,
          ),
        ),
      );
      expect(gateway.signOutCalled, isTrue);
    });

    test('updatePassword is called exactly once, never retried', () async {
      gateway.updatePasswordError = const NotAuthorizedServiceException(
        'irrelevant',
      );
      gateway.sessionCheckResult = true;

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(isA<AuthFailure>()),
      );

      expect(gateway.updatePasswordCallCount, 1);
    });

    test(
      'the diagnostic session refresh is attempted at most once, never looped',
      () async {
        gateway.updatePasswordError = const NotAuthorizedServiceException(
          'irrelevant',
        );
        gateway.sessionCheckResult = true;

        await expectLater(
          repository.changePassword(currentPassword, newPassword),
          throwsA(isA<AuthFailure>()),
        );

        expect(gateway.sessionCheckCallCount, 1);
      },
    );

    test(
      'the session check is never triggered by other exception types',
      () async {
        gateway.updatePasswordError = const InvalidPasswordException(
          'bad policy',
        );

        await expectLater(
          repository.changePassword(currentPassword, newPassword),
          throwsA(isA<AuthFailure>()),
        );

        expect(gateway.sessionCheckCallCount, 0);
      },
    );
  });

  test(
    'maps SignedOutException to notAuthenticated and invalidates the session',
    () async {
      gateway.updatePasswordError = const SignedOutException(
        'No user signed in',
      );

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.notAuthenticated,
          ),
        ),
      );
      expect(gateway.signOutCalled, isTrue);
      expect(gateway.sessionCheckCallCount, 0);
    },
  );

  test('maps InvalidPasswordException to invalidPassword', () async {
    gateway.updatePasswordError = const InvalidPasswordException(
      'Password does not conform to policy',
    );

    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.kind,
          'kind',
          AuthFailureKind.invalidPassword,
        ),
      ),
    );
  });

  test(
    'maps PasswordHistoryPolicyViolationException to invalidPassword',
    () async {
      gateway.updatePasswordError =
          const PasswordHistoryPolicyViolationException('reused password');

      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidPassword,
          ),
        ),
      );
    },
  );

  test(
    'maps LimitExceededException and TooManyRequestsException to rateLimited',
    () async {
      gateway.updatePasswordError = const LimitExceededException('slow down');
      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );

      gateway.updatePasswordError = const TooManyRequestsException('slow down');
      await expectLater(
        repository.changePassword(currentPassword, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );
    },
  );

  test('maps NetworkException to unavailable', () async {
    gateway.updatePasswordError = const NetworkException('offline');

    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.kind,
          'kind',
          AuthFailureKind.unavailable,
        ),
      ),
    );
  });

  test('maps an unrecognized AuthException to unknown', () async {
    gateway.updatePasswordError = const UnknownException('boom');

    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.kind,
          'kind',
          AuthFailureKind.unknown,
        ),
      ),
    );
  });

  test('no resulting AuthFailure ever contains the current or new password, '
      'nor the raw Cognito exception message', () async {
    const oddMessage = 'zzz-arbitrary-cognito-wording-zzz';
    final scenarios = <Object>[
      const NotAuthorizedServiceException(oddMessage),
      const SignedOutException(oddMessage),
      const InvalidPasswordException(oddMessage),
      const PasswordHistoryPolicyViolationException(oddMessage),
      const LimitExceededException(oddMessage),
      const NetworkException(oddMessage),
      const UnknownException(oddMessage),
    ];

    for (final scenario in scenarios) {
      gateway.updatePasswordError = scenario;
      gateway.sessionCheckResult = false;
      try {
        await repository.changePassword(currentPassword, newPassword);
        fail('expected changePassword to throw for $scenario');
      } on AuthFailure catch (failure) {
        expect(failure.toString(), isNot(contains(currentPassword)));
        expect(failure.toString(), isNot(contains(newPassword)));
        expect(failure.toString(), isNot(contains(oddMessage)));
        expect(failure.safeMessage, isNot(contains(currentPassword)));
        expect(failure.safeMessage, isNot(contains(newPassword)));
        expect(failure.safeMessage, isNot(contains(oddMessage)));
      }
    }
  });

  test('session-expired and not-authenticated failures both route through the '
      'same central invalidateSession() the app already uses for a 401 from '
      'the API client, while a wrong-password failure never does', () async {
    gateway
      ..updatePasswordError = const NotAuthorizedServiceException('irrelevant')
      ..sessionCheckResult = false;
    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(isA<AuthFailure>()),
    );
    expect(gateway.signOutCalled, isTrue, reason: 'sessionExpired');

    gateway
      ..signOutCalled = false
      ..updatePasswordError = const SignedOutException('No user signed in');
    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(isA<AuthFailure>()),
    );
    expect(gateway.signOutCalled, isTrue, reason: 'notAuthenticated');

    gateway
      ..signOutCalled = false
      ..updatePasswordError = const NotAuthorizedServiceException('irrelevant')
      ..sessionCheckResult = true;
    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(isA<AuthFailure>()),
    );
    expect(gateway.signOutCalled, isFalse, reason: 'incorrectCurrentPassword');
  });
}
