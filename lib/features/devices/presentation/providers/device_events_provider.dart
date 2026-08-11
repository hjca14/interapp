import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/device_event.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';

/// Loads recent events for a device and keeps merging in live ones,
/// deduplicated by `event_id` (see [dedupeDeviceEvents]).
///
/// Backs the "Eventos recentes" card in `DeviceDetailPage`: today
/// `LocalDeviceBackendRepository` returns an empty history and an empty
/// live stream, so the card keeps showing "Nenhum evento recebido" — this
/// provider exists so that swapping in a real `DeviceBackendRepository`
/// later makes real events show up without any UI change.
class DeviceEventsController extends AsyncNotifier<List<DeviceEvent>> {
  DeviceEventsController(this.deviceId);

  final String deviceId;
  StreamSubscription<DeviceEvent>? _subscription;

  @override
  Future<List<DeviceEvent>> build() async {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
    });
    final repository = ref.read(deviceBackendRepositoryProvider);
    final recent = await repository.getRecentEvents(deviceId);
    _subscription = repository.watchDeviceEvents(deviceId).listen(_onLiveEvent);
    return dedupeDeviceEvents(recent);
  }

  void _onLiveEvent(DeviceEvent event) {
    final current = state.value ?? const <DeviceEvent>[];
    state = AsyncData(dedupeDeviceEvents([event, ...current]));
  }
}

final deviceEventsProvider =
    AsyncNotifierProvider.family<
      DeviceEventsController,
      List<DeviceEvent>,
      String
    >(DeviceEventsController.new);
