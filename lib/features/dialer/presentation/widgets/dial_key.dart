import 'package:flutter/material.dart';

class DialKey extends StatelessWidget {
  const DialKey({super.key, required this.value, required this.letters, required this.onTap});
  final String value;
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
