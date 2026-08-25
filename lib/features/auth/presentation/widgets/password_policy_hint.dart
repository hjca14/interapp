import 'package:flutter/material.dart';

/// Static password-policy hint shared by sign-up, password reset, and
/// password change. Cognito's User Pool policy remains the sole authority —
/// this text is informational only and is never used for local validation.
class PasswordPolicyHint extends StatelessWidget {
  const PasswordPolicyHint({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Use ao menos 8 caracteres, com letra maiúscula, minúscula e número. '
      'Símbolo é opcional.',
    );
  }
}
