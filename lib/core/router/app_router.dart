import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/presentation/pages/device_detail_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/home/presentation/pages/home_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (_, _) => const HomePage(),
      ),
      GoRoute(
        path: '/devices/:deviceId',
        name: 'device-detail',
        builder: (context, state) {
          final device = state.extra! as InterBridgeDevice;
          return DeviceDetailPage(
            device: device,
            favoritesRepository: ref.read(favoritesRepositoryProvider),
          );
        },
      ),
    ],
  );
});
