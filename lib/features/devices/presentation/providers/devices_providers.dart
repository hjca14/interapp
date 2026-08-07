import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/data/repositories/local_devices_repository.dart';
import 'package:interapp/features/favorites/data/repositories/local_favorites_repository.dart';
import 'package:interapp/features/profile/data/repositories/local_profile_repository.dart';

final devicesRepositoryProvider = Provider<LocalDevicesRepository>(
  (_) => LocalDevicesRepository(),
);

final favoritesRepositoryProvider = Provider<LocalFavoritesRepository>(
  (_) => LocalFavoritesRepository(),
);

final profileRepositoryProvider = Provider<LocalProfileRepository>(
  (_) => LocalProfileRepository(),
);
