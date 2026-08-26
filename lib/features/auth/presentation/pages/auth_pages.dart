import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/password_policy_hint.dart';
import '../widgets/password_visibility_field.dart';

/// E-mail and password login screen.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(_emailController.text.trim(), _passwordController.text);
      _passwordController.clear();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.safeMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Entrar',
      children: [
        _EmailField(controller: _emailController),
        PasswordVisibilityField(
          controller: _passwordController,
          label: 'Senha',
          autofillHint: AutofillHints.password,
          onSubmitted: _submitting ? null : _submit,
        ),
        _InlineError(message: _errorMessage),
        _SubmitButton(
          submitting: _submitting,
          idleLabel: 'Entrar',
          onPressed: _submit,
        ),
        TextButton(
          onPressed: () => context.push('/sign-up'),
          child: const Text('Criar conta'),
        ),
        TextButton(
          onPressed: () => context.push('/forgot-password'),
          child: const Text('Esqueci minha senha'),
        ),
      ],
    );
  }
}

/// E-mail sign-up screen that continues to code confirmation.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final email = _emailController.text.trim();
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(email, _passwordController.text);
      _passwordController.clear();
      if (mounted) {
        context.push('/confirm', extra: email);
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.safeMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Criar conta',
      children: [
        _EmailField(controller: _emailController),
        PasswordVisibilityField(
          controller: _passwordController,
          label: 'Senha',
          autofillHint: AutofillHints.newPassword,
        ),
        const PasswordPolicyHint(),
        _InlineError(message: _errorMessage),
        _SubmitButton(
          submitting: _submitting,
          idleLabel: 'Cadastrar',
          busyLabel: 'Cadastrando...',
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Confirmation-code screen shared by sign-up and password reset.
class CodePage extends ConsumerStatefulWidget {
  const CodePage({super.key, required this.email, this.passwordReset = false});

  final String email;
  final bool passwordReset;

  @override
  ConsumerState<CodePage> createState() => _CodePageState();
}

class _CodePageState extends ConsumerState<CodePage> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (widget.passwordReset) {
        await auth.confirmPasswordReset(
          widget.email,
          _codeController.text.trim(),
          _passwordController.text,
        );
        _passwordController.clear();
      } else {
        await auth.confirmSignUp(widget.email, _codeController.text.trim());
      }
      if (mounted) {
        context.go('/login');
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.safeMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    try {
      await ref.read(authRepositoryProvider).resendSignUpCode(widget.email);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Código reenviado.')));
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.safeMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: widget.passwordReset ? 'Definir nova senha' : 'Confirmar e-mail',
      children: [
        const Text('Enviamos um código para o e-mail informado.'),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Código'),
        ),
        if (widget.passwordReset) ...[
          PasswordVisibilityField(
            controller: _passwordController,
            label: 'Senha',
            autofillHint: AutofillHints.newPassword,
          ),
          const PasswordPolicyHint(),
        ],
        _InlineError(message: _errorMessage),
        _SubmitButton(
          submitting: _submitting,
          idleLabel: 'Confirmar',
          onPressed: _submit,
        ),
        if (!widget.passwordReset)
          TextButton(
            onPressed: _submitting ? null : _resendCode,
            child: const Text('Reenviar código'),
          ),
      ],
    );
  }
}

/// Begins password recovery without adding account-enumeration hints.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final email = _emailController.text.trim();
    try {
      await ref.read(authRepositoryProvider).beginPasswordReset(email);
      if (mounted) {
        context.push('/reset', extra: email);
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _errorMessage = failure.safeMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Redefinir senha',
      children: [
        const Text(
          'Informe seu e-mail. Se o fluxo puder continuar, enviaremos um código.',
        ),
        _EmailField(controller: _emailController),
        _InlineError(message: _errorMessage),
        _SubmitButton(
          submitting: _submitting,
          idleLabel: 'Enviar código',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: children
                .map(
                  (child) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: child,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      decoration: const InputDecoration(labelText: 'E-mail'),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Text(
      message!,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.submitting,
    required this.idleLabel,
    required this.onPressed,
    this.busyLabel = 'Aguarde...',
  });

  final bool submitting;
  final String idleLabel;
  final String busyLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: submitting ? null : onPressed,
      child: Text(submitting ? busyLabel : idleLabel),
    );
  }
}
