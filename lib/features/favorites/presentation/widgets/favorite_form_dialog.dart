import 'package:flutter/material.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';

class FavoriteFormDialog extends StatefulWidget {
  const FavoriteFormDialog({super.key, this.favorite});
  final Favorite? favorite;

  @override
  State<FavoriteFormDialog> createState() => _FavoriteFormDialogState();
}

class _FavoriteFormDialogState extends State<FavoriteFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _numberController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.favorite?.name);
    _numberController = TextEditingController(text: widget.favorite?.number);
  }

  void _save() {
    final name = _nameController.text.trim();
    final number = _numberController.text.trim();
    if (name.isEmpty || number.isEmpty) return;
    Navigator.of(context).pop(Favorite(name: name, number: number));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.favorite == null ? 'Novo favorito' : 'Editar favorito'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.phone,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(labelText: 'Telefone ou ramal'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
        ],
      );
}
