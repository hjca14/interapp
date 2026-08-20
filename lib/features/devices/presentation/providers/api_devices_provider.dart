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
      final page = await ref.read(httpDeviceRepositoryProvider).list();
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
          .read(httpDeviceRepositoryProvider)
          .list(cursor: requestedCursor);
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

final apiDeviceDetailProvider =
    FutureProvider.family<ApiDeviceDetail, String>((ref, deviceId) {
      return ref.watch(httpDeviceRepositoryProvider).detail(deviceId);
    });

final apiDeviceStatusProvider =
    FutureProvider.family<ApiDeviceStatus, String>((ref, deviceId) {
      return ref.watch(httpDeviceRepositoryProvider).status(deviceId);
    });
