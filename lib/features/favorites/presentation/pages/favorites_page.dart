import 'dart:async';

import 'package:flutter/material.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';
import 'package:interapp/features/favorites/presentation/widgets/favorite_form_dialog.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.repository, required this.deviceId, required this.onDialFavorite});
  final LocalFavoritesRepository repository;
  final String? deviceId;
  final ValueChanged<String> onDialFavorite;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Favorite> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
  }

  @override
  void didUpdateWidget(covariant FavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      unawaited(_loadFavorites());
    }
  }

  Future<void> _loadFavorites() async {
    if (widget.deviceId == null) {
      if (mounted) {
        setState(() {
          _favorites = [];
          _loading = false;
        });
      }
      return;
    }
    final favorites = await widget.repository.getAll(widget.deviceId!);
    if (mounted) setState(() { _favorites = favorites; _loading = false; });
  }

  Future<void> _save() => widget.repository.saveAll(widget.deviceId!, _favorites);

  Future<void> _editFavorite({Favorite? favorite}) async {
    if (widget.deviceId == null) return;
    final result = await showDialog<Favorite>(
      context: context,
      builder: (_) => FavoriteFormDialog(favorite: favorite),
    );
    if (result == null) return;
    setState(() {
      if (favorite == null) {
        _favorites.add(result);
      } else {
        _favorites[_favorites.indexOf(favorite)] = result;
      }
    });
    try {
      await _save();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar o favorito.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (widget.deviceId == null) {
      return const Center(child: Text('Selecione ou adicione um dispositivo para ver seus favoritos.'));
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _editFavorite, child: const Icon(Icons.add)),
      body: _favorites.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_outline, size: 56), const SizedBox(height: 12), const Text('Nenhum favorito ainda'),
              TextButton.icon(onPressed: _editFavorite, icon: const Icon(Icons.add), label: const Text('Adicionar favorito')),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(12), itemCount: _favorites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final favorite = _favorites[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(favorite.name[0].toUpperCase())), title: Text(favorite.name), subtitle: Text(favorite.number),
                  onTap: () => widget.onDialFavorite(favorite.number),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') await _editFavorite(favorite: favorite);
                      if (action == 'remove') { setState(() => _favorites.remove(favorite)); await _save(); }
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar')), PopupMenuItem(value: 'remove', child: Text('Remover'))],
                  ),
                );
              },
            ),
    );
  }
}
