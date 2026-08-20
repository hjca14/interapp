import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';

void main() {
  test('fake starts signed out and supports login and logout', () async {
    final repository = LocalAuthRepository();

    expect((await repository.currentSession).isSignedIn, isFalse);
    await repository.signIn('person@example.invalid', 'NotAReal1');
    expect((await repository.currentSession).isSignedIn, isTrue);
    await repository.signOut();
    expect((await repository.currentSession).isSignedIn, isFalse);
  });

  test('fake covers signup, confirmation and reset without network', () async {
    final repository = LocalAuthRepository();

    final signUpResult = await repository.signUp(
      'person@example.invalid',
      'NotAReal1',
    );
    expect(signUpResult.confirmationRequired, isTrue);
    await repository.confirmSignUp('person@example.invalid', '000000');
    await repository.resendSignUpCode('person@example.invalid');
    await repository.beginPasswordReset('person@example.invalid');
    await repository.confirmPasswordReset(
      'person@example.invalid',
      '000000',
      'Another1',
    );
  });
}
