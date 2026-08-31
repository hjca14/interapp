import 'package:flutter/foundation.dart';

import 'ring_call_intent.dart';

typedef RingDeviceAuthorizer = Future<bool> Function(String deviceId);
typedef RingCallClock = DateTime Function();

/// Holds at most one minimal ring intent until both authentication and an
/// authenticated device lookup succeed. It is UI/router agnostic and never
/// retains an FCM payload.
final class RingCallNavigationCoordinator extends ChangeNotifier {
  RingCallNavigationCoordinator(
    this._authorizeDevice, {
    RingCallClock? now,
    Duration maxAge = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now,
       _maxAge = maxAge;

  final RingDeviceAuthorizer _authorizeDevice;
  final RingCallClock _now;
  final Duration _maxAge;
  RingCallIntent? _pending;
  RingCallIntent? _active;
  bool _authenticated = false;
  int _generation = 0;

  RingCallIntent? get active => _active;
  bool get hasPending => _pending != null;
  bool get shouldOpen => _active != null;

  void acceptSerialized(String? payload, {DateTime? now}) {
    final intent = RingCallIntent.tryRestore(
      payload,
      now: now ?? _now(),
      maxAge: _maxAge,
    );
    if (intent == null) return;
    _pending = intent;
    _active = null;
    _resolve();
  }

  void setAuthenticated(bool value) {
    _authenticated = value;
    if (!value) {
      _generation++;
      _active = null;
      notifyListeners();
      return;
    }
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
    if (authorized && _isRecent(intent)) _active = intent;
    notifyListeners();
  }

  bool _isRecent(RingCallIntent intent) =>
      RingCallIntent.tryRestore(
        intent.serialize(),
        now: _now(),
        maxAge: _maxAge,
      ) !=
      null;

  void consumed() {
    _active = null;
    notifyListeners();
  }
}
