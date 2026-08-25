import 'package:flutter/material.dart';

/// A password [TextField] that starts obscured, offers a show/hide toggle,
/// and disables autocorrect/suggestions — shared by every screen that
/// collects a Cognito password so the behavior can't drift between them.
class PasswordVisibilityField extends StatefulWidget {
  const PasswordVisibilityField({
    super.key,
    required this.controller,
    required this.label,
    required this.autofillHint,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String autofillHint;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordVisibilityField> createState() =>
      _PasswordVisibilityFieldState();
}

class _PasswordVisibilityFieldState extends State<PasswordVisibilityField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: !_visible,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [widget.autofillHint],
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Ocultar senha' : 'Mostrar senha',
          onPressed: () {
            setState(() {
              _visible = !_visible;
            });
          },
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }
}
