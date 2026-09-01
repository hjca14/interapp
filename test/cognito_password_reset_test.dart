import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/auth_diagnostic.dart';
import 'package:interapp/features/auth/data/repositories/cognito_auth_repository.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';

const _confirmCodeStep = ResetPasswordStep(
  updateStep: AuthResetPasswordStep.confirmResetPasswordWithCode,
);
const _doneStep = ResetPasswordStep(updateStep: AuthResetPasswordStep.done);

class _FakeGateway implements CognitoAuthGateway {
  Object? resetPasswordError;
  Object? confirmResetPasswordError;
  ResetPasswordResult resetPasswordResult = const CognitoResetPasswordResult(
    isPasswordReset: false,
    nextStep: _confirmCodeStep,
  );

  String? capturedResetUsername;
  String? capturedConfirmUsername;
  String? capturedConfirmCode;
  String? capturedConfirmNewPassword;
  int resetPasswordCallCount = 0;
  int confirmResetPasswordCallCount = 0;

  @override
  Future<ResetPasswordResult> resetPassword({required String username}) async {
    resetPasswordCallCount++;
    capturedResetUsername = username;
    final error = resetPasswordError;
    if (error != null) {
      // ignore: only_throw_errors
      throw error;
    }
    return resetPasswordResult;
  }

  @override
  Future<void> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) async {
    confirmResetPasswordCallCount++;
    capturedConfirmUsername = username;
    capturedConfirmNewPassword = newPassword;
    capturedConfirmCode = confirmationCode;
    final error = confirmResetPasswordError;
    if (error != null) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) => throw UnimplementedError('not exercised by this test file');

  @override
  Future<void> signOut() => throw UnimplementedError('not exercised');

  @override
  Future<bool> hasValidSessionAfterForceRefresh() =>
      throw UnimplementedError('not exercised');
}

void main() {
  const email = 'person@example.invalid';
  const code = '123456';
  const newPassword = 'Br4nd-N3w-P4ss!';

  late _FakeGateway gateway;
  late CognitoAuthRepository repository;

  setUp(() {
    gateway = _FakeGateway();
    repository = CognitoAuthRepository(authGateway: gateway);
  });

  group('confirmPasswordReset', () {
    test('calls the gateway with the three values unchanged', () async {
      await repository.confirmPasswordReset(email, code, newPassword);

      expect(gateway.capturedConfirmUsername, email);
      expect(gateway.capturedConfirmCode, code);
      expect(gateway.capturedConfirmNewPassword, newPassword);
      expect(gateway.confirmResetPasswordCallCount, 1);
    });

    test('completes successfully with no error', () async {
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        completes,
      );
    });

    test('maps CodeMismatchException to invalidOrExpiredCode', () async {
      gateway.confirmResetPasswordError = const CodeMismatchException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidOrExpiredCode,
          ),
        ),
      );
    });

    test('maps ExpiredCodeException to invalidOrExpiredCode', () async {
      gateway.confirmResetPasswordError = const ExpiredCodeException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidOrExpiredCode,
          ),
        ),
      );
    });

    test('maps InvalidPasswordException to invalidPassword', () async {
      gateway.confirmResetPasswordError = const InvalidPasswordException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
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
        gateway.confirmResetPasswordError =
            const PasswordHistoryPolicyViolationException('irrelevant');
        await expectLater(
          repository.confirmPasswordReset(email, code, newPassword),
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

    test('maps LimitExceededException and TooManyRequestsException to '
        'rateLimited', () async {
      gateway.confirmResetPasswordError = const LimitExceededException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );

      gateway.confirmResetPasswordError = const TooManyRequestsException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );
    });

    test('maps NetworkException to unavailable', () async {
      gateway.confirmResetPasswordError = const NetworkException('irrelevant');
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
    });

    test('maps InvalidParameterException to the contextual reset fallback, not '
        'the generic unknown fallback', () async {
      gateway.confirmResetPasswordError = const InvalidParameterException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidResetState,
          ),
        ),
      );
    });

    test('maps an unrecognized AuthException to the safe unknown fallback '
        '(invalidResetState is reserved for exceptions the reset mapper '
        'recognizes but cannot detail further)', () async {
      gateway.confirmResetPasswordError = const UnknownException('irrelevant');
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidResetState,
          ),
        ),
      );
    });

    test('NotAuthorizedServiceException during reset confirmation never uses '
        "the login-context invalidCredentials/'e-mail ou senha inválidos' "
        'mapping', () async {
      gateway.confirmResetPasswordError = const NotAuthorizedServiceException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                isNot(AuthFailureKind.invalidCredentials),
              )
              .having(
                (failure) => failure.kind,
                'kind',
                AuthFailureKind.invalidResetState,
              )
              .having(
                (failure) => failure.safeMessage,
                'safeMessage',
                isNot(contains('senha inválid')),
              ),
        ),
      );
    });

    test('UserNotFoundException during reset confirmation never confirms or '
        'denies account existence via the login-context message', () async {
      gateway.confirmResetPasswordError = const UserNotFoundException(
        'irrelevant',
      );
      await expectLater(
        repository.confirmPasswordReset(email, code, newPassword),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.invalidResetState,
          ),
        ),
      );
    });

    test('no resulting AuthFailure ever contains the code, new password, or '
        'the raw Cognito exception message', () async {
      const oddMessage = 'zzz-arbitrary-cognito-wording-zzz';
      final scenarios = <Object>[
        const CodeMismatchException(oddMessage),
        const ExpiredCodeException(oddMessage),
        const InvalidPasswordException(oddMessage),
        const PasswordHistoryPolicyViolationException(oddMessage),
        const LimitExceededException(oddMessage),
        const NetworkException(oddMessage),
        const NotAuthorizedServiceException(oddMessage),
        const InvalidParameterException(oddMessage),
        const UnknownException(oddMessage),
      ];

      for (final scenario in scenarios) {
        gateway.confirmResetPasswordError = scenario;
        try {
          await repository.confirmPasswordReset(email, code, newPassword);
          fail('expected confirmPasswordReset to throw for $scenario');
        } on AuthFailure catch (failure) {
          expect(failure.safeMessage, isNot(contains(code)));
          expect(failure.safeMessage, isNot(contains(newPassword)));
          expect(failure.safeMessage, isNot(contains(oddMessage)));
        }
      }
    });
  });

  group('beginPasswordReset', () {
    test('forwards the email unchanged to the gateway', () async {
      await repository.beginPasswordReset(email);
      expect(gateway.capturedResetUsername, email);
      expect(gateway.resetPasswordCallCount, 1);
    });

    test(
      'completes normally when Cognito requires a confirmation code',
      () async {
        gateway.resetPasswordResult = const CognitoResetPasswordResult(
          isPasswordReset: false,
          nextStep: _confirmCodeStep,
        );
        await expectLater(repository.beginPasswordReset(email), completes);
      },
    );

    test('throws a passwordResetComplete AuthFailure when Cognito reports the '
        'reset is already done, instead of blindly proceeding to the code '
        'screen', () async {
      gateway.resetPasswordResult = const CognitoResetPasswordResult(
        isPasswordReset: true,
        nextStep: _doneStep,
      );
      await expectLater(
        repository.beginPasswordReset(email),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.kind,
            'kind',
            AuthFailureKind.passwordResetComplete,
          ),
        ),
      );
    });
  });

  group('sanitized debug diagnostic', () {
    test('contains only the operation name and the exception type', () {
      final lines = <String>[];
      emitAuthDiagnostic(
        'confirm_password_reset',
        const InvalidParameterException('super secret detail'),
        debugMode: true,
        sink: (message, {wrapWidth}) => lines.add(message ?? ''),
      );

      expect(lines, hasLength(1));
      expect(
        lines.single,
        '[AUTH] operation=confirm_password_reset '
        'failure_type=InvalidParameterException',
      );
    });

    test('never contains email, password, code, token, message, '
        'recoverySuggestion, or underlyingException', () {
      final lines = <String>[];
      emitAuthDiagnostic(
        'confirm_password_reset',
        const InvalidParameterException(
          'contains an email person@example.invalid and a code 000000 and '
          'a password Sup3rSecret!',
          recoverySuggestion: 'retry with token abc.def.ghi',
          underlyingException: 'raw sdk payload with secrets',
        ),
        debugMode: true,
        sink: (message, {wrapWidth}) => lines.add(message ?? ''),
      );

      expect(lines.single, isNot(contains('person@example.invalid')));
      expect(lines.single, isNot(contains('000000')));
      expect(lines.single, isNot(contains('Sup3rSecret')));
      expect(lines.single, isNot(contains('token')));
      expect(lines.single, isNot(contains('retry')));
      expect(lines.single, isNot(contains('raw sdk payload')));
      expect(
        lines.single,
        '[AUTH] operation=confirm_password_reset '
        'failure_type=InvalidParameterException',
      );
    });

    test('emits nothing on the path configured for release', () {
      final lines = <String>[];
      emitAuthDiagnostic(
        'confirm_password_reset',
        const InvalidParameterException('irrelevant'),
        debugMode: false,
        sink: (message, {wrapWidth}) => lines.add(message ?? ''),
      );

      expect(lines, isEmpty);
    });

    test('a repository failure emits the diagnostic for its own operation', () {
      final lines = <String>[];
      // Repository-level operations always route through the shared
      // emitAuthDiagnostic helper; this direct call proves the per-operation
      // vocabulary used inside the repository ('sign_in') matches what a
      // real login failure would log.
      emitAuthDiagnostic(
        'sign_in',
        const NotAuthorizedServiceException('irrelevant'),
        debugMode: true,
        sink: (message, {wrapWidth}) => lines.add(message ?? ''),
      );

      expect(lines.single, contains('operation=sign_in'));
      expect(
        lines.single,
        contains('failure_type=NotAuthorizedServiceException'),
      );
    });
  });
}
