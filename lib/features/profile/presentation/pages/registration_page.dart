import 'package:flutter/material.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

/// Asks for the user's display name — shown once on first launch (no
/// [initialName]) and reused for "editar perfil" from Ajustes (with
/// [initialName] pre-filled). Pops with the saved name so the caller can
/// update its own state without re-reading storage.
class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, this.initialName});
  final String? initialName;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _repository = LocalProfileRepository();
  late final TextEditingController _nameController;

  /// Disables the button and swaps its label while the (usually instant)
  /// `shared_preferences` write is in flight.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  /// Trims and validates the name, persists it, then pops with the saved
  /// value. No-ops silently on an empty name (the button just stays put)
  /// rather than showing a validation error, since this is a single required
  /// field.
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await _repository.saveName(name);
    if (mounted) Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.initialName == null ? 'Cadastro' : 'Editar perfil')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Icon(Icons.person_outline, size: 72),
                const SizedBox(height: 24),
                Text(
                  widget.initialName == null ? 'Bem-vindo ao InterBridge' : 'Seu perfil',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(labelText: 'Como podemos chamar você?'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Salvando...' : 'Continuar'),
                ),
              ],
            ),
          ),
        ),
      );
}
