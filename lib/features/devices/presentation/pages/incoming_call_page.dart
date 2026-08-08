import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen "ringing" UI shown while the app is open and the device
/// reports an incoming call.
///
/// There is no real audio/call channel yet (Fase 3 do roadmap), so both
/// actions only dismiss the ringing state for now.
class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.deviceName,
    required this.onDismiss,
  });

  final String deviceName;
  final VoidCallback onDismiss;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  Timer? _ringTimer;

  @override
  void initState() {
    super.initState();
    _ring();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) => _ring());
  }

  void _ring() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    widget.onDismiss();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1246A8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              children: [
                const Spacer(),
                const Icon(Icons.speaker_phone, color: Colors.white, size: 72),
                const SizedBox(height: 24),
                Text(
                  'Chamada recebida',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.deviceName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallAction(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'Recusar',
                      onPressed: _dismiss,
                    ),
                    _CallAction(
                      icon: Icons.call,
                      color: Colors.green,
                      label: 'Atender',
                      onPressed: _dismiss,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: color,
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
