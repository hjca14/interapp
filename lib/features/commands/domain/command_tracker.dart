import 'dart:async';

import '../data/command_repository.dart';
import 'command_models.dart';

abstract interface class CommandScheduler {
  Future<void> wait(Duration duration);
}

final class TimerCommandScheduler implements CommandScheduler {
  const TimerCommandScheduler();

  @override
  Future<void> wait(Duration duration) => Future<void>.delayed(duration);
}

final class CommandTrackingCancelled implements Exception {
  const CommandTrackingCancelled();
}

/// Bounded polling for an already-created command. Only COMPLETED can indicate
/// conclusion; PENDING/202 or an MQTT publish cannot. With firmware disabled,
/// REJECTED/CAPABILITY_DISABLED is the expected fail-closed outcome.
final class CommandTracker {
  CommandTracker({
    required CommandRepository repository,
    CommandScheduler scheduler = const TimerCommandScheduler(),
    DateTime Function()? now,
    Stream<void>? logoutEvents,
    this.pollInterval = const Duration(seconds: 1),
    this.totalLimit = const Duration(seconds: 30),
  }) : _repository = repository,
       _scheduler = scheduler,
       _now = now ?? DateTime.now {
    _logoutSubscription = logoutEvents?.listen((_) => cancel());
  }

  final CommandRepository _repository;
  final CommandScheduler _scheduler;
  final DateTime Function() _now;
  final Duration pollInterval;
  final Duration totalLimit;
  StreamSubscription<void>? _logoutSubscription;
  Completer<void> _cancelled = Completer<void>();
  bool _disposed = false;

  Future<CommandStatus?> track(DeviceId deviceId, CommandId commandId) async {
    if (_disposed) {
      throw const CommandTrackingCancelled();
    }
    final deadline = _now().add(totalLimit);
    while (_now().isBefore(deadline)) {
      await Future.any([_scheduler.wait(pollInterval), _cancelled.future]);
      if (_cancelled.isCompleted) {
        throw const CommandTrackingCancelled();
      }
      final status = await _repository.getCommand(deviceId, commandId);
      if (status.isTerminal) {
        return status;
      }
    }
    return null;
  }

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    cancel();
    await _logoutSubscription?.cancel();
  }
}
