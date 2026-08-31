import 'package:flutter/services.dart';

/// Whether this Android installation currently holds the special
/// `USE_FULL_SCREEN_INTENT` access (Android 14+; always true below that,
/// where it was a normal install-time permission). Never throws — an
/// unavailable channel (older platform, non-Android target, a plugin that
/// failed to attach) degrades to `false`, the safe default that keeps the
/// ring notification a plain heads-up alert instead of a full-screen one.
typedef FullScreenIntentChecker = Future<bool> Function();

const _channel = MethodChannel('interapp/full_screen_intent');

/// Talks to `MainActivity`'s own channel (not part of
/// `flutter_local_notifications` — that plugin only exposes
/// `requestFullScreenIntentPermission()`, which navigates to Settings
/// whenever access is missing). This is read-only and never navigates.
Future<bool> checkFullScreenIntentAccess() async {
  try {
    return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;
  } on Object {
    return false;
  }
}
