import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/cognito_auth_repository.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

class _FakeGateway implements CognitoAuthGateway {
  Object? updatePasswordError;
  bool signOutCalled = false;
  String? capturedOldPassword;
  String? capturedNewPassword;

  @override
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
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

  test(
    'maps a wrong-current-password NotAuthorizedException to incorrectCurrentPassword '
    'without invalidating the session',
    () async {
      gateway.updatePasswordError = const NotAuthorizedServiceException(
        'Incorrect username or password.',
      );

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

  test('maps an ambiguous NotAuthorizedException to sessionExpired and '
      'invalidates the session centrally', () async {
    gateway.updatePasswordError = const NotAuthorizedServiceException(
      'Access Token has expired',
    );

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

  test(
    'no resulting AuthFailure ever contains the current or new password text',
    () async {
      final scenarios = <Object>[
        const NotAuthorizedServiceException('Incorrect username or password.'),
        const NotAuthorizedServiceException('Access Token has expired'),
        const SignedOutException('No user signed in'),
        const InvalidPasswordException('bad policy'),
        const PasswordHistoryPolicyViolationException('reused'),
        const LimitExceededException('slow down'),
        const NetworkException('offline'),
        const UnknownException('boom'),
      ];

      for (final scenario in scenarios) {
        gateway.updatePasswordError = scenario;
        try {
          await repository.changePassword(currentPassword, newPassword);
          fail('expected changePassword to throw for $scenario');
        } on AuthFailure catch (failure) {
          expect(failure.toString(), isNot(contains(currentPassword)));
          expect(failure.toString(), isNot(contains(newPassword)));
          expect(failure.safeMessage, isNot(contains(currentPassword)));
          expect(failure.safeMessage, isNot(contains(newPassword)));
        }
      }
    },
  );

  test('session-expired and not-authenticated failures both route through the '
      'same central invalidateSession() the app already uses for a 401 from '
      'the API client, while a wrong-password failure never does', () async {
    gateway.updatePasswordError = const NotAuthorizedServiceException(
      'Access Token has expired',
    );
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
      ..updatePasswordError = const NotAuthorizedServiceException(
        'Incorrect username or password.',
      );
    await expectLater(
      repository.changePassword(currentPassword, newPassword),
      throwsA(isA<AuthFailure>()),
    );
    expect(gateway.signOutCalled, isFalse, reason: 'incorrectCurrentPassword');
  });
}
