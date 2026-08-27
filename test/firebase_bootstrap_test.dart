import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/firebase_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a Firebase bootstrap failure is swallowed instead of thrown', () async {
    // No platform channel is registered for firebase_core in this unit
    // test environment, so this exercises the real failure path without
    // talking to Firebase.
    final result = await FirebaseBootstrap.configure();

    expect(result, isFalse);
  });
}
