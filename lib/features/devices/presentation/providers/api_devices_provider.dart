import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/api_device.dart';
import 'devices_providers.dart';

/// Complete UI state for the paginated device list.
class DeviceListState {
  const DeviceListState({
    this.items = const [],
    this.nextCursor,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
  });

  final List<ApiDeviceSummary> items;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Object? loadMoreError;
}

/// Loads and paginates authenticated devices without persisting cursors.
class ApiDevicesController extends Notifier<DeviceListState> {
  bool _requestInFlight = false;

  @override
  DeviceListState build() {
    Future.microtask(refresh);
    return const DeviceListState();
  }

  /// Restarts pagination from the first page and drops the old cursor.
  Future<void> refresh() async {
    if (_requestInFlight) {
      return;
    }
    _requestInFlight = true;
    state = const DeviceListState();
    try {
      final page = await ref.read(deviceRepositoryProvider).listDevices();
      state = DeviceListState(
        items: _deduplicateByDeviceId(page.items),
        nextCursor: page.nextCursor,
        loading: false,
      );
    } on Object catch (error) {
      state = DeviceListState(loading: false, error: error);
    } finally {
      _requestInFlight = false;
    }
  }

  /// Loads one additional page while preserving existing items on failure.
  Future<void> loadMore() async {
    final requestedCursor = state.nextCursor;
    if (requestedCursor == null || _requestInFlight) {
      return;
    }

    _requestInFlight = true;
    state = DeviceListState(
      items: state.items,
      nextCursor: requestedCursor,
      loading: false,
      loadingMore: true,
    );
    try {
      final page = await ref
          .read(deviceRepositoryProvider)
          .listDevices(cursor: requestedCursor);
      // A repeated opaque cursor indicates no forward progress. Clearing it
      // prevents a pagination loop without attempting to interpret its value.
      final nextCursor = page.nextCursor == requestedCursor
          ? null
          : page.nextCursor;
      state = DeviceListState(
        items: _deduplicateByDeviceId([...state.items, ...page.items]),
        nextCursor: nextCursor,
        loading: false,
      );
    } on Object catch (error) {
      state = DeviceListState(
        items: state.items,
        nextCursor: requestedCursor,
        loading: false,
        loadMoreError: error,
      );
    } finally {
      _requestInFlight = false;
    }
  }

  /// Reflects a successful rename (or name clear) from
  /// [ApiDeviceDetailController.updateName] in the already-loaded list,
  /// without a network round trip. A no-op if the device isn't loaded yet.
  void applyRenamedDevice(String deviceId, String? displayName) {
    state = DeviceListState(
      items: [
        for (final item in state.items)
          if (item.deviceId == deviceId)
            ApiDeviceSummary(
              deviceId: item.deviceId,
              displayName: displayName,
              role: item.role,
              status: item.status,
            )
          else
            item,
      ],
      nextCursor: state.nextCursor,
      loading: state.loading,
      loadingMore: state.loadingMore,
      error: state.error,
      loadMoreError: state.loadMoreError,
    );
  }

  static List<ApiDeviceSummary> _deduplicateByDeviceId(
    Iterable<ApiDeviceSummary> devices,
  ) {
    final seenIds = <String>{};
    return devices
        .where((device) => seenIds.add(device.deviceId))
        .toList(growable: false);
  }
}

final apiDevicesProvider =
    NotifierProvider<ApiDevicesController, DeviceListState>(
      ApiDevicesController.new,
    );

/// Loads one device's details and, unlike a plain read-only provider, also
/// carries [updateName] — the friendly-name edit needs to write through the
/// repository and reflect the confirmed result immediately. See
/// `DeviceSettingsController` for the same read+write `AsyncNotifier` shape
/// used elsewhere in this feature.
class ApiDeviceDetailController extends AsyncNotifier<ApiDeviceDetail> {
  ApiDeviceDetailController(this.deviceId);

  final String deviceId;

  @override
  Future<ApiDeviceDetail> build() {
    return ref.watch(deviceRepositoryProvider).getDeviceDetails(deviceId);
  }

  /// Renames the device, or clears its custom name when [displayName] is
  /// `null`. Waits for the repository to confirm the write before touching
  /// `state` — no optimistic update, so a failure never shows a name the
  /// backend didn't actually save. If the repository call throws, `state`
  /// simply never changes, so the previous value (and whatever the edit
  /// screen's own text field still holds) is untouched.
  Future<void> updateName(String? displayName) async {
    final updated = await ref
        .read(deviceRepositoryProvider)
        .updateDeviceName(deviceId, displayName);
    state = AsyncData(updated);
    ref
        .read(apiDevicesProvider.notifier)
        .applyRenamedDevice(deviceId, updated.displayName);
  }
}

final apiDeviceDetailProvider =
    AsyncNotifierProvider.family<
      ApiDeviceDetailController,
      ApiDeviceDetail,
      String
    >(ApiDeviceDetailController.new);

final apiDeviceStatusProvider = FutureProvider.family<ApiDeviceStatus, String>((
  ref,
  deviceId,
) {
  return ref.watch(httpDeviceRepositoryProvider).status(deviceId);
});
