import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const officialId = 'com.interbridge.app';

  test(
    'Android uses the official application id, namespace, package and name',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/interbridge/app/MainActivity.kt',
      ).readAsStringSync();

      expect(gradle, contains('namespace = "$officialId"'));
      expect(gradle, contains('applicationId = "$officialId"'));
      expect(manifest, contains('android:label="InterBridge"'));
      expect(activity, startsWith('package $officialId'));
      expect(activity, contains('"interapp/device_timezone"'));
      expect(
        File(
          'android/app/src/main/kotlin/com/example/interapp/MainActivity.kt',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('iOS uses the official Runner and test bundle identifiers and name', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      RegExp(
        'PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(officialId)};',
      ).allMatches(project),
      hasLength(3),
    );
    expect(
      RegExp(
        'PRODUCT_BUNDLE_IDENTIFIER = '
        '${RegExp.escape(officialId)}\\.RunnerTests;',
      ).allMatches(project),
      hasLength(3),
    );
    expect(info, contains('<string>InterBridge</string>'));
    expect(project, isNot(contains('com.example.interapp')));
  });

  test('Phase 3B.3 configures Firebase for Android only', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final googleServices = File(
      'android/app/google-services.json',
    ).readAsStringSync();
    final firebaseOptions = File(
      'lib/firebase_options.dart',
    ).readAsStringSync();

    expect(pubspec, contains('firebase_core'));
    expect(pubspec, contains('firebase_messaging'));
    expect(googleServices, contains(officialId));
    expect(firebaseOptions, contains('interbridge-dev'));
    expect(firebaseOptions, contains('static const FirebaseOptions android'));
    expect(
      File('ios/Runner/GoogleService-Info.plist').existsSync(),
      isFalse,
    );
  });
}
