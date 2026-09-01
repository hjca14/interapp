import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/devices/data/services/incoming_call_notification_service.dart';
import '../../firebase_options.dart';
import 'installation_id_store.dart' show SharedPreferencesStringStore;
import 'ring_call_tombstone.dart';
import 'ring_detected_presenter.dart';
import 'ring_event_deduplicator.dart';

/// Handles a data/notification message while the app is not running.
///
/// Must stay top-level so the Android engine can spawn it in a background
/// isolate, which has no access to UI, providers, or `BuildContext` and
/// re-initializes Firebase on its own. Reuses the exact same parser,
/// deduplicator, and [IncomingCallNotificationService] presenter as the
/// foreground path (`PushNotificationService`) via
/// [presentRingDetectedPush] — nothing is duplicated between the two. Only
/// ever emits a debug-only, sanitized diagnostic; no AWS/API call is made,
/// and nothing is persisted beyond the small dedup record described in
/// `ring_event_deduplicator.dart`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final presenter = IncomingCallNotificationService(
      FlutterLocalNotificationsPlugin(),
    );
    // Channel/plugin setup only — no permission prompt from an isolate with
    // no UI to show one over.
    await presenter.initializeForBackgroundIsolate();

    final preferences = await SharedPreferences.getInstance();
    final deduplicator = SharedPreferencesRingEventDeduplicator(
      SharedPreferencesStringStore(preferences),
    );
    final tombstones = SharedPreferencesRingCallTombstoneStore(preferences);

    await presentRingDetectedPush(
      data: message.data,
      presenter: presenter,
      deduplicator: deduplicator,
      tombstones: tombstones,
      path: 'background_handler',
      onDiagnostic: (diagnostic) {
        if (kDebugMode) {
          debugPrint(diagnostic.toLogLine());
        }
      },
    );
  } on Object {
    // Sanitized on purpose: this isolate has no UI and nobody to report to
    // — it must never crash or let a raw exception surface.
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
