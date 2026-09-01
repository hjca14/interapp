import 'package:flutter/services.dart';

/// Whether this Android installation currently holds the special
/// `USE_FULL_SCREEN_INTENT` access (Android 14+; always true below that,
/// where it was a normal install-time permission). Never throws — an
/// unavailable channel (older platform, non-Android target, a plugin that
/// failed to attach, or `MainActivity` simply not being alive) degrades to
/// `false`.
///
/// This powers `SecuritySettingsPage`'s informational status only — see
/// `IncomingCallNotificationService.hasFullScreenIntentAccess`. It does
/// **not** decide whether a `RING_DETECTED` push requests full-screen
/// presentation: `IncomingCallNotificationService.present` always requests
/// it for `RING_ONLY`/`RING_AND_NOTIFICATION` and lets Android itself
/// degrade to a heads-up alert when access isn't held, precisely because
/// this MethodChannel's handler lives only in `MainActivity` and has no
/// guarantee of being registered when a push arrives through the FCM
/// background isolate with the app backgrounded/closed and the device
/// locked.
typedef FullScreenIntentChecker = Future<bool> Function();

const _channel = MethodChannel('interapp/full_screen_intent');

/// Talks to `MainActivity`'s own channel (not part of
/// `flutter_local_notifications` — that plugin only exposes
/// `requestFullScreenIntentPermission()`, which navigates to Settings
/// whenever access is missing). This is read-only and never navigates, and
/// must never be called as a dependency of receiving or presenting a push —
/// see the class-level doc above.
Future<bool> checkFullScreenIntentAccess() async {
  try {
    return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;
  } on Object {
    return false;
  }
}
