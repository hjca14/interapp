import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ring_call_intent.dart';

typedef RingDeviceAuthorizer = Future<bool> Function(String deviceId);
typedef RingCallClock = DateTime Function();

/// Holds at most one minimal ring intent until both authentication and an
/// authorized device lookup succeed, and locally times out a call 60s after
/// it occurred if nothing else ends it first. It is UI/router agnostic and
/// never retains an FCM payload.
///
/// Single-slot by design: this app shows at most one call at a time. A new
/// [acceptSerialized] for a different `call_id` than whatever is currently
/// pending/active supersedes it (the older call is dropped locally — its own
/// notification is unaffected, since notification lifecycle is entirely
/// `IncomingCallNotificationService`'s concern, driven independently by the
/// same pushes). A new [acceptSerialized] for the *same* `call_id` is
/// treated as an update: it reschedules the single ring-timeout timer from
/// the new payload's `occurredAt` rather than starting a second one.
final class RingCallNavigationCoordinator extends ChangeNotifier {
  RingCallNavigationCoordinator(
    this._authorizeDevice, {
    RingCallClock? now,
    this._ringTimeout = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final RingDeviceAuthorizer _authorizeDevice;
  final RingCallClock _now;
  final Duration _ringTimeout;
  RingCallIntent? _pending;
  RingCallIntent? _active;
  bool _authenticated = false;
  int _generation = 0;
  Timer? _ringTimeoutTimer;

  RingCallIntent? get active => _active;
  bool get hasPending => _pending != null;
  bool get shouldOpen => _active != null;

  /// The `call_id` this coordinator is currently pending or active on, or
  /// `null` when it is holding nothing. External listeners (see
  /// `ringCallEndIntegrationProvider`) diff this across [notifyListeners]
  /// calls to notice exactly when a call — pending or active — stops being
  /// tracked here, including via the internal ring-timeout, which has no
  /// other external signal of its own.
  String? get trackedCallId => _active?.callId ?? _pending?.callId;

  /// True while a call is confirmed pending (authenticated, not yet
  /// timed out) but still being authorized against the device repository —
  /// the brief async gap the UI must cover with a neutral, non-interactive
  /// surface instead of revealing whatever screen was underneath. See
  /// `RingCallOverlay`.
  bool get isValidating => _authenticated && _pending != null;

  void acceptSerialized(String? payload, {DateTime? now}) {
    final reference = now ?? _now();
    final intent = RingCallIntent.tryRestore(
      payload,
      now: reference,
      maxAge: _ringTimeout,
    );
    if (intent == null) return;
    // Already showing this exact call (e.g. the user tapped its notification
    // a second time) — nothing to do, and no reason to flicker the call
    // screen away and back while re-authorizing it.
    if (_active?.callId == intent.callId) return;
    _pending = intent;
    _active = null;
    // Uses the same [reference] just validated against, rather than
    // re-sampling [_now()] a second time — a caller-supplied [now] override
    // (tests) must govern the whole call, not just the restore step.
    _scheduleRingTimeout(intent, reference);
    // Announce the new pending/validating state immediately — [_resolve]
    // only notifies once its async authorization settles, but the UI
    // (`RingCallOverlay`) must cover the screen with a neutral surface
    // starting from this exact call, not only once resolution finishes.
    notifyListeners();
    _resolve();
  }

  void setAuthenticated(bool value) {
    _authenticated = value;
    if (!value) {
      _generation++;
      _active = null;
      _pending = null;
      _cancelRingTimeout();
      notifyListeners();
      return;
    }
    // Same reasoning as [acceptSerialized]: if a call was already pending
    // while logged out, becoming authenticated now flips [isValidating] to
    // true immediately, before [_resolve]'s async authorization settles.
    if (_pending != null) notifyListeners();
    _resolve();
  }

  Future<void> _resolve() async {
    final intent = _pending;
    if (!_authenticated || intent == null) return;
    // A tap may have waited for login. Revalidate the typed minimal context
    // before doing even the authenticated device lookup, rather than treating
    // validation at notification-receipt time as permanently valid.
    if (!_isRecent(intent)) {
      _generation++;
      _pending = null;
      _cancelRingTimeout();
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    var authorized = false;
    try {
      authorized = await _authorizeDevice(intent.deviceId);
    } on Object {
      authorized = false;
    }
    if (generation != _generation || !_authenticated || _pending != intent) {
      return;
    }
    _pending = null;
    // Authorization itself can take long enough for the ring to expire.
    // Never promote a stale intent to navigation after that await either.
    if (authorized && _isRecent(intent)) {
      _active = intent;
    } else {
      _cancelRingTimeout();
    }
    notifyListeners();
  }

  bool _isRecent(RingCallIntent intent) =>
      RingCallIntent.tryRestore(
        intent.serialize(),
        now: _now(),
        maxAge: _ringTimeout,
      ) !=
      null;

  /// Ends the call named by [callId] — from a remote `RING_ENDED`, the local
  /// ring-timeout, or the user answering/dismissing. A no-op if [callId]
  /// does not match whatever is currently pending/active: a stale end for an
  /// earlier call must never cancel a newer, unrelated one, and an end for a
  /// call this coordinator never held (e.g. `NOTIFICATION_ONLY` never
  /// reaches here) is simply nothing to do.
  void endCall(String callId) {
    var changed = false;
    if (_pending?.callId == callId) {
      _pending = null;
      _generation++;
      changed = true;
    }
    if (_active?.callId == callId) {
      _active = null;
      changed = true;
    }
    if (changed) {
      _cancelRingTimeout();
      notifyListeners();
    }
  }

  /// Stops the local ring-timeout for [callId] without ending the call: the
  /// user answered (there is nothing left to "ring" for), but this
  /// placeholder build has no real audio session to hang up on its own —
  /// see `IncomingCallPage._answer`. The call stays [active] until the user
  /// explicitly dismisses it or a `RING_ENDED` arrives. A no-op if [callId]
  /// is not the currently active call.
  void markAnswered(String callId) {
    if (_active?.callId != callId) return;
    _cancelRingTimeout();
  }

  void _scheduleRingTimeout(RingCallIntent intent, DateTime reference) {
    _cancelRingTimeout();
    final elapsed = reference.difference(intent.occurredAt);
    final remaining = _ringTimeout - elapsed;
    if (remaining <= Duration.zero) {
      // Already expired by the time it was accepted (e.g. a slow cold
      // start) — end it on the next microtask rather than synchronously
      // inside acceptSerialized, so callers observing `hasPending`
      // immediately after this call see it as briefly pending, then ended,
      // consistent with every other timeout path.
      _ringTimeoutTimer = Timer(Duration.zero, () => endCall(intent.callId));
      return;
    }
    _ringTimeoutTimer = Timer(remaining, () => endCall(intent.callId));
  }

  void _cancelRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
  }

  void consumed() {
    if (_active == null) return;
    _cancelRingTimeout();
    _active = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelRingTimeout();
    super.dispose();
  }
}
