import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/change_password_controller.dart';
import '../widgets/password_policy_hint.dart';
import '../widgets/password_visibility_field.dart';

/// Lets a signed-in user change their password by providing the current one,
/// via the real Cognito `updatePassword` operation. Distinct from
/// [ForgotPasswordPage]/[CodePage], which recover access for someone who
/// doesn't know their current password.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() {
    return ref
        .read(changePasswordControllerProvider.notifier)
        .submit(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
          confirmPassword: _confirmController.text,
        );
  }

  void _onSuccess() {
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    _currentController.clear();
    _newController.clear();
    _confirmController.clear();
    Navigator.of(context).maybePop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Senha alterada com sucesso.')),
    );
  }

  Future<void> _confirmForgotPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Não lembra sua senha?'),
        content: const Text(
          'A recuperação por e-mail exige sair da sua conta atual. Deseja '
          'sair agora para continuar pela tela de login?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair e continuar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(changePasswordControllerProvider, (previous, next) {
      if (next.isSuccess && previous?.isSuccess != true) {
        _onSuccess();
      }
    });
    final state = ref.watch(changePasswordControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alterar senha')),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              PasswordVisibilityField(
                key: const Key('current-password-field'),
                controller: _currentController,
                label: 'Senha atual',
                autofillHint: AutofillHints.password,
                errorText: state.currentPasswordError,
                enabled: !state.isSubmitting,
                textInputAction: TextInputAction.next,
                onSubmitted: () => _newFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordVisibilityField(
                key: const Key('new-password-field'),
                controller: _newController,
                focusNode: _newFocus,
                label: 'Nova senha',
                autofillHint: AutofillHints.newPassword,
                errorText: state.newPasswordError,
                enabled: !state.isSubmitting,
                textInputAction: TextInputAction.next,
                onSubmitted: () => _confirmFocus.requestFocus(),
              ),
              const SizedBox(height: 8),
              const PasswordPolicyHint(),
              const SizedBox(height: 16),
              PasswordVisibilityField(
                key: const Key('confirm-password-field'),
                controller: _confirmController,
                focusNode: _confirmFocus,
                label: 'Confirmar nova senha',
                autofillHint: AutofillHints.newPassword,
                errorText: state.confirmPasswordError,
                enabled: !state.isSubmitting,
                textInputAction: TextInputAction.done,
                onSubmitted: state.isSubmitting ? null : _submit,
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.isSubmitting ? null : _submit,
                child: state.isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Alterar senha'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: state.isSubmitting ? null : _confirmForgotPassword,
                  child: const Text('Não lembra sua senha?'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
