import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/presentation/pages/incoming_call_page.dart';
import 'package:interapp/features/devices/presentation/providers/device_status_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// Reacts to [DeviceStatus.hasIncomingCall] changes for [deviceId]: shows a
/// full-screen ringing UI while [child] is on screen and fires a local
/// notification so the call can be noticed if the app is backgrounded.
///
/// This only works while the app process is alive. Waking the app from a
/// fully closed state requires a remote push from a backend, which does not
/// exist yet (Fase 4 do roadmap) — see [IncomingCallNotificationService].
class IncomingCallListener extends ConsumerStatefulWidget {
  const IncomingCallListener({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.child,
  });

  final String deviceId;
  final String deviceName;
  final Widget child;

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  /// Tracks whether [IncomingCallPage] is currently pushed, so a second
  /// status update while it's already open doesn't push it twice, and so
  /// [_handleCallEnded] knows whether there's anything to pop.
  bool _callPageOpen = false;

  @override
  Widget build(BuildContext context) {
    // `ref.listen` (not `ref.watch`) because this widget doesn't want to
    // rebuild on every status change — it only wants to run side effects
    // (navigate, notify) at the moment `hasIncomingCall` flips.
    ref.listen<AsyncValue<DeviceStatus>>(
      deviceStatusProvider(widget.deviceId),
      (previous, next) {
        final wasRinging = previous?.value?.hasIncomingCall ?? false;
        final isRinging = next.value?.hasIncomingCall ?? false;
        if (isRinging && !wasRinging) {
          _handleIncomingCall();
        } else if (!isRinging && wasRinging) {
          _handleCallEnded();
        }
      },
    );
    return widget.child;
  }

  /// `hasIncomingCall` just turned `true`: notify (works even if the app is
  /// backgrounded) and, if the ringing page isn't already showing, push it.
  void _handleIncomingCall() {
    ref
        .read(incomingCallNotificationServiceProvider)
        .showIncomingCall(widget.deviceId, widget.deviceName);
    if (_callPageOpen) {
      return;
    }
    _callPageOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => IncomingCallPage(
              deviceName: widget.deviceName,
              onDismiss: _dismissedByUser,
            ),
          ),
        )
        // Runs when the route is popped by any means (this callback or the
        // page's own Atender/Recusar buttons), keeping the flag in sync.
        .then((_) => _callPageOpen = false);
  }

  /// Passed to [IncomingCallPage] as `onDismiss`: the user tapped
  /// Atender/Recusar. The page pops itself, so this only clears local state
  /// and cancels the notification — it must NOT also call `Navigator.pop`,
  /// or the page would be popped twice.
  void _dismissedByUser() {
    _callPageOpen = false;
    ref
        .read(incomingCallNotificationServiceProvider)
        .cancelIncomingCall(widget.deviceId);
  }

  /// `hasIncomingCall` just turned `false` from the device side (e.g. the
  /// debug simulation timed out, or a real caller hung up) rather than from
  /// the user dismissing the page. Cancels the notification and, if the
  /// ringing page is still open, closes it automatically.
  void _handleCallEnded() {
    ref
        .read(incomingCallNotificationServiceProvider)
        .cancelIncomingCall(widget.deviceId);
    if (_callPageOpen) {
      _callPageOpen = false;
      Navigator.of(context).maybePop();
    }
  }
}
