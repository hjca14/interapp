import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runApp is called before the FCM permission/token initialization, '
      'so the first frame never waits on it', () {
    final source = File('lib/main.dart').readAsStringSync();

    final firebaseBootstrapIndex = source.indexOf(
      'FirebaseBootstrap.configure()',
    );
    final runAppIndex = source.indexOf('runApp(');
    final pushInitializeIndex = source.indexOf(
      'pushNotificationServiceProvider).initialize()',
    );

    expect(firebaseBootstrapIndex, isNonNegative);
    expect(runAppIndex, isNonNegative);
    expect(pushInitializeIndex, isNonNegative);

    // Registering the background handler is local plugin setup required
    // by firebase_messaging before runApp. Permission/token work must
    // start only after the UI is already up, not before.
    expect(firebaseBootstrapIndex, lessThan(runAppIndex));
    expect(runAppIndex, lessThan(pushInitializeIndex));

    expect(source, contains('unawaited('));
  });
}
