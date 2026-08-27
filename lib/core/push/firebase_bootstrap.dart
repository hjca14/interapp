import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Handles a data/notification message while the app is not running.
///
/// Must stay top-level so the Android engine can spawn it in a background
/// isolate, which has no access to UI, providers, or `BuildContext` and
/// re-initializes Firebase on its own. Only emits a debug-only marker —
/// nothing is persisted, no AWS call is made.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    debugPrint(
      '[FCM][DEBUG-ONLY] background_handler messageId=${message.messageId ?? '-'}',
    );
  }
}

/// Initializes the Firebase app and wires the FCM background handler.
///
/// Never throws: a missing or broken Firebase project must not prevent
/// login, device listing, or the rest of the app from working.
class FirebaseBootstrap {
  static Future<bool> configure() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      return true;
    } on Object {
      return false;
    }
  }
}
