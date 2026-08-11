import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/favorites/domain/entities/favorite.dart';

void main() {
  group('Favorite storage round-trip', () {
    test('toStorage/fromStorage preserves name and number', () {
      const favorite = Favorite(name: 'Portaria', number: '1234');

      final decoded = Favorite.fromStorage(favorite.toStorage());

      expect(decoded, isNotNull);
      expect(decoded!.name, 'Portaria');
      expect(decoded.number, '1234');
    });

    test('fromStorage returns null for malformed entries', () {
      expect(Favorite.fromStorage(''), isNull);
      expect(Favorite.fromStorage('only-one-part'), isNull);
      expect(Favorite.fromStorage('\t1234'), isNull);
      expect(Favorite.fromStorage('Portaria\t'), isNull);
      expect(Favorite.fromStorage('a\tb\tc'), isNull);
    });
  });
}
