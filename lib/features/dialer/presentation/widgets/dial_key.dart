import 'package:flutter/material.dart';

/// One key of the dialer keypad: a big digit (or `*`/`#`) with the small
/// letter row underneath (e.g. "2" / "ABC"), like a classic phone keypad.
class DialKey extends StatelessWidget {
  const DialKey({super.key, required this.value, required this.letters, required this.onTap});

  /// The digit/symbol shown large and appended to the number on tap.
  final String value;

  /// The small letter hint under [value] (empty for `1`, `*`, `#`).
  final String letters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 30)),
            SizedBox(
              height: 14,
              child: Text(
                letters,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      );
}
