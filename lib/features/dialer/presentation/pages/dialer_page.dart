import 'package:flutter/material.dart';
import 'package:interapp/features/dialer/presentation/controllers/dialer_controller.dart';
import 'package:interapp/features/dialer/presentation/widgets/dial_key.dart';

/// The "Discar" tab: a phone-style keypad for typing a number to dial
/// through the InterBridge.
///
/// This is **not** the OS phone dialer — no `tel:` link, no launching the
/// Telefone app. The green call button is currently a placeholder (shows a
/// snackbar); wiring it to `DeviceConnectionRepository.dial` is a future
/// integration point once there's a real transport.
class DialerPage extends StatelessWidget {
  const DialerPage({super.key, required this.controller});
  final DialerController controller;

  /// (key label, small letters under it) for each of the 12 keypad buttons,
  /// in reading order.
  static const _keys = [
    ('1', ''), ('2', 'ABC'), ('3', 'DEF'),
    ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'),
    ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
    ('*', ''), ('0', '+'), ('#', ''),
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // DialerPage is a StatelessWidget; AnimatedBuilder is what makes it
        // rebuild whenever `controller` (a ChangeNotifier) calls
        // notifyListeners(), e.g. after a key tap or a favorite filling in
        // a number from outside this widget.
        animation: controller,
        builder: (context, _) => Column(
        children: [
          const SizedBox(height: 20),
          SizedBox(
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    controller.number.isEmpty ? 'Digite o número' : controller.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      letterSpacing: 1.5,
                      color: controller.number.isEmpty ? Theme.of(context).hintColor : null,
                    ),
                  ),
                ),
                IconButton(onPressed: controller.deleteLast, icon: const Icon(Icons.backspace_outlined)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 1.28,
                physics: const NeverScrollableScrollPhysics(),
                children: _keys
                    .map((key) => DialKey(value: key.$1, letters: key.$2, onTap: () => controller.append(key.$1)))
                    .toList(),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Conexão com o InterBridge será implementada aqui.')),
            ),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(20),
              backgroundColor: Colors.green.shade700,
            ),
            child: const Icon(Icons.call, size: 30),
          ),
          const SizedBox(height: 16),
        ],
      ),
      );
}
