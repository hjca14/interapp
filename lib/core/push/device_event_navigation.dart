import 'package:flutter/foundation.dart';

import 'notification_tap_diagnostic.dart';

typedef DeviceAuthorizer = Future<bool> Function(String deviceId);

/// Holds at most one pending device-detail navigation intent until
/// authentication is confirmed — mirroring `RingCallNavigationCoordinator`'s
/// own pending/authenticated pattern, but for a `NOTIFICATION_ONLY` tap
/// ([DeviceEventNotificationIntent]) rather than a call. Simpler than that
/// coordinator on purpose: a device-event tap carries no `RingCallIntent`
/// freshness window of its own (no ring-timeout to race), so the only gate
/// before navigating is "is authentication known, and is this account still
/// authorized to see this device" — never a guess, never navigated while
/// authentication is still being restored (e.g. right after a cold start).
///
/// Router-agnostic: [target] exposes the deviceId once authorized, and a
/// listener (see `deviceEventNavigationIntegrationProvider`) is responsible
/// for actually calling the router and then [consumed].
final class DeviceEventNavigationCoordinator extends ChangeNotifier {
  DeviceEventNavigationCoordinator(this._authorizeDevice, {this.onDiagnostic});

  final DeviceAuthorizer _authorizeDevice;
  final void Function(NotificationTapDiagnostic diagnostic)? onDiagnostic;

  String? _pendingDeviceId;
  String? _target;
  bool _authenticated = false;
  int _generation = 0;

  /// The deviceId ready to navigate to, or `null` when nothing is pending
  /// or authorization has not yet resolved. Cleared by [consumed].
  String? get target => _target;

  /// Called when a `NOTIFICATION_ONLY` notification is tapped. If
  /// authentication is not yet confirmed, the intent is preserved (not
  /// discarded) until [setAuthenticated] resolves it — see class doc.
  void acceptDeviceId(String deviceId) {
    _pendingDeviceId = deviceId;
    if (!_authenticated) {
      onDiagnostic?.call(
        NotificationTapDiagnostic.pendingAwaitingAuthentication(),
      );
    }
    _resolve();
  }

  /// A logout ([value] == false) discards any pending intent — this app
  /// never resumes a device-event navigation across a real sign-out; the
  /// user lands on the login screen like any other unauthenticated route,
  /// exactly the same policy [RingCallNavigationCoordinator] already
  /// applies to a pending call.
  void setAuthenticated(bool value) {
    _authenticated = value;
    if (!value) {
      _generation++;
      _pendingDeviceId = null;
      _target = null;
      return;
    }
    _resolve();
  }

  Future<void> _resolve() async {
    final deviceId = _pendingDeviceId;
    if (!_authenticated || deviceId == null) return;
    final generation = ++_generation;
    var authorized = false;
    try {
      authorized = await _authorizeDevice(deviceId);
    } on Object {
      authorized = false;
    }
    if (generation != _generation ||
        !_authenticated ||
        _pendingDeviceId != deviceId) {
      return;
    }
    _pendingDeviceId = null;
    if (!authorized) {
      onDiagnostic?.call(NotificationTapDiagnostic.deviceNotAuthorized());
      return;
    }
    _target = deviceId;
    notifyListeners();
  }

  /// Clears [target] once a listener has actually navigated to it.
  void consumed() {
    _target = null;
  }
}
