import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalProfileRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getName() returns null when nothing was saved', () async {
      final repository = LocalProfileRepository();

      expect(await repository.getName(), isNull);
    });

    test('saveName() then getName() round-trips', () async {
      final repository = LocalProfileRepository();

      await repository.saveName('Helena');

      expect(await repository.getName(), 'Helena');
    });
  });
}
