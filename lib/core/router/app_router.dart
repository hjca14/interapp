import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/presentation/pages/device_detail_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/home/presentation/pages/home_page.dart';

/// All app navigation goes through this single [GoRouter] instance.
///
/// Two routes exist today:
/// * `/` — [HomePage], the devices list + settings tabs.
/// * `/devices/:deviceId` — [DeviceDetailPage] for one device.
///
/// The device is currently passed through `GoRouterState.extra` instead of
/// being looked up by `deviceId` (see the builder below). That's fine while
/// devices only live in local storage; once there's a backend, this route
/// should fetch the device by id so a deep link/notification tap can open it
/// without the caller having the object in memory already.
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
          // `extra` is set by the caller (see HomePage._openDevice); the `!`
          // is safe today because this route is only ever reached that way.
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
