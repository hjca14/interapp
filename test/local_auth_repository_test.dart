import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';

void main() {
  group('LocalAuthRepository', () {
    test(
      'reports no session instead of fabricating a signed-in user',
      () async {
        final repository = LocalAuthRepository();

        expect(await repository.currentSession, isNull);
        expect(await repository.watchSession().first, isNull);
      },
    );

    test(
      'signIn is loudly unsupported rather than silently pretending to work',
      () {
        final repository = LocalAuthRepository();

        expect(() => repository.signIn(), throwsUnsupportedError);
      },
    );
  });
}
