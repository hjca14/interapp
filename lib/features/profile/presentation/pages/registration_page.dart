import 'package:flutter/material.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, this.initialName});
  final String? initialName;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _repository = LocalProfileRepository();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

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
