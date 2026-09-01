import 'package:flutter/services.dart';

const _channel = MethodChannel('interapp/ring_call_presentation');

/// Tells `MainActivity` a call is no longer being presented (answered,
/// dismissed, remotely ended, or locally timed out) so it can drop
/// `setShowWhenLocked`/`setTurnScreenOn` and — if the device is still
/// actually locked — return to the system keyguard, instead of leaving the
/// app visible over/behind a now-stale lock-screen bypass.
///
/// Safe to call unconditionally, for every call end, regardless of whether
/// this particular call was ever shown over a locked keyguard:
/// `MainActivity`'s handler only acts (moves the task back) when the device
/// is still actually locked; otherwise it is a no-op and the app simply
/// keeps showing whatever is now underneath the dismissed call overlay.
/// Never throws — a missing channel (older platform, non-Android target, a
/// plugin that failed to attach) is silently ignored, since there is no
/// native lock-screen bypass to undo there either.
Future<void> endRingCallLockScreenPresentation() async {
  try {
    await _channel.invokeMethod<void>('endPresentation');
  } on Object {
    // See doc comment above — nothing to undo, nothing to report.
  }
}
