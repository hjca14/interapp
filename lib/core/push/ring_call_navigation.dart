import 'package:flutter/foundation.dart';

import 'ring_call_intent.dart';

typedef RingDeviceAuthorizer = Future<bool> Function(String deviceId);

/// Holds at most one minimal ring intent until both authentication and an
/// authenticated device lookup succeed. It is UI/router agnostic and never
/// retains an FCM payload.
final class RingCallNavigationCoordinator extends ChangeNotifier {
  RingCallNavigationCoordinator(this._authorizeDevice);

  final RingDeviceAuthorizer _authorizeDevice;
  RingCallIntent? _pending;
  RingCallIntent? _active;
  bool _authenticated = false;
  int _generation = 0;

  RingCallIntent? get active => _active;
  bool get hasPending => _pending != null;
  bool get shouldOpen => _active != null;

  void acceptSerialized(String? payload, {DateTime? now}) {
    final intent = RingCallIntent.tryRestore(payload, now: now);
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
    if (authorized) _active = intent;
    notifyListeners();
  }

  void consumed() {
    _active = null;
    notifyListeners();
  }
}
