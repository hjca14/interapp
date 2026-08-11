import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalFavoritesRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getAll() returns an empty list when nothing was saved', () async {
      final repository = LocalFavoritesRepository();

      expect(await repository.getAll('device-1'), isEmpty);
    });

    test(
      'saveAll() then getAll() round-trips favorites for that device',
      () async {
        final repository = LocalFavoritesRepository();
        const favorites = [
          Favorite(name: 'Portaria', number: '1234'),
          Favorite(name: 'Portão', number: '5678'),
        ];

        await repository.saveAll('device-1', favorites);
        final reloaded = await repository.getAll('device-1');

        expect(reloaded.map((favorite) => favorite.name), [
          'Portaria',
          'Portão',
        ]);
      },
    );

    test('favorites are isolated per device', () async {
      final repository = LocalFavoritesRepository();

      await repository.saveAll('device-a', const [
        Favorite(name: 'A', number: '1'),
      ]);
      await repository.saveAll('device-b', const [
        Favorite(name: 'B', number: '2'),
      ]);

      expect((await repository.getAll('device-a')).single.name, 'A');
      expect((await repository.getAll('device-b')).single.name, 'B');
    });
  });
}
