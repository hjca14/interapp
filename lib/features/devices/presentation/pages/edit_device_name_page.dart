import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/api_device.dart';
import '../providers/api_devices_provider.dart';

/// Edits (or clears) the authenticated user's personal name for one device.
///
/// Pushed from the detail screen with the device's current [initialName].
/// Pops with no return value on success: unlike `RegistrationPage`, the
/// saved name lives in Riverpod state (`apiDeviceDetailProvider`), which the
/// caller already watches, so there's nothing to hand back.
class EditDeviceNamePage extends ConsumerStatefulWidget {
  const EditDeviceNamePage({
    super.key,
    required this.deviceId,
    required this.initialName,
  });

  final String deviceId;
  final String? initialName;

  @override
  ConsumerState<EditDeviceNamePage> createState() => _EditDeviceNamePageState();
}

class _EditDeviceNamePageState extends ConsumerState<EditDeviceNamePage> {
  late final TextEditingController _nameController;
  bool _saving = false;

  bool get _hasCustomName =>
      widget.initialName != null && widget.initialName!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _nameController.text.trim().isNotEmpty;

  Future<void> _save() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      return Future.value();
    }
    return _submit(trimmed);
  }

  Future<void> _useDefaultName() => _submit(null);

  /// [displayName] is either a trimmed, non-empty name or `null` — this
  /// method never sends an empty string, since the backend contract only
  /// treats `null` as "clear the personal name".
  Future<void> _submit(String? displayName) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(apiDeviceDetailProvider(widget.deviceId).notifier)
          .updateName(displayName);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar o nome. Tente novamente.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editar nome')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Esse nome aparece somente na sua conta.'),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              autofocus: true,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              maxLength: kDeviceDisplayNameMaxLength,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Nome para você',
                hintText: 'Ex.: Minha casa',
              ),
            ),
            if (_hasCustomName)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saving ? null : _useDefaultName,
                  child: const Text('Usar nome padrão'),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(_saving ? 'Salvando...' : 'Salvar'),
            ),
          ],
        ),
      ),
    ),
  );
}
