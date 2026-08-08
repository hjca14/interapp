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
  bool _callPageOpen = false;

  @override
  Widget build(BuildContext context) {
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

  void _handleIncomingCall() {
    ref
        .read(incomingCallNotificationServiceProvider)
        .showIncomingCall(widget.deviceId, widget.deviceName);
    if (_callPageOpen) return;
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
        .then((_) => _callPageOpen = false);
  }

  void _dismissedByUser() {
    _callPageOpen = false;
    ref
        .read(incomingCallNotificationServiceProvider)
        .cancelIncomingCall(widget.deviceId);
  }

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
