import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';

import 'api_devices_provider.dart';

class DeviceRefreshCoordinator {
  DeviceRefreshCoordinator(this.ref, this.deviceId);

  final Ref ref;
  final String deviceId;
  Future<ApiDeviceStatus>? _statusRequest;

  Future<ApiDeviceStatus> refreshStatus() {
    return _statusRequest ??= _performStatusRefresh();
  }

  Future<ApiDeviceStatus> _performStatusRefresh() async {
    try {
      final status = await ref.refresh(
        apiDeviceStatusProvider(deviceId).future,
      );
      return status;
    } finally {
      _statusRequest = null;
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      ref.refresh(apiDeviceDetailProvider(deviceId).future),
      refreshStatus(),
    ]);
  }
}

final deviceRefreshCoordinatorProvider =
    Provider.family<DeviceRefreshCoordinator, String>(
      DeviceRefreshCoordinator.new,
    );

abstract interface class StatusPollingHandle {
  void cancel();
}

abstract interface class StatusPollingScheduler {
  StatusPollingHandle periodic(Duration interval, void Function() callback);
}

class TimerStatusPollingScheduler implements StatusPollingScheduler {
  const TimerStatusPollingScheduler();

  @override
  StatusPollingHandle periodic(Duration interval, void Function() callback) {
    return _TimerPollingHandle(Timer.periodic(interval, (_) => callback()));
  }
}

class _TimerPollingHandle implements StatusPollingHandle {
  const _TimerPollingHandle(this.timer);
  final Timer timer;

  @override
  void cancel() => timer.cancel();
}

final statusPollingSchedulerProvider = Provider<StatusPollingScheduler>(
  (ref) => const TimerStatusPollingScheduler(),
);
