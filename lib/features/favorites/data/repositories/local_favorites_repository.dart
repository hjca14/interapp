import 'package:interapp/features/favorites/domain/entities/favorite.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalFavoritesRepository {
  static const _favoritesKeyPrefix = 'favorites_';

  Future<List<Favorite>> getAll(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList('$_favoritesKeyPrefix$deviceId') ?? [])
        .map(Favorite.fromStorage)
        .whereType<Favorite>()
        .toList();
  }

  Future<void> saveAll(String deviceId, List<Favorite> favorites) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      '$_favoritesKeyPrefix$deviceId',
      favorites.map((favorite) => favorite.toStorage()).toList(),
    );
  }
}
