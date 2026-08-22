import 'dart:async';

import '../data/command_repository.dart';
import 'command_models.dart';

abstract interface class CommandScheduler {
  Future<void> wait(Duration duration);
}

abstract interface class CancellableCommandScheduler {
  void cancelWaits();
}

final class TimerCommandScheduler
    implements CommandScheduler, CancellableCommandScheduler {
  Timer? _timer;
  Completer<void>? _wait;

  @override
  Future<void> wait(Duration duration) {
    final wait = Completer<void>();
    _wait = wait;
    _timer = Timer(duration, () {
      _timer = null;
      _wait = null;
      wait.complete();
    });
    return wait.future;
  }

  @override
  void cancelWaits() {
    _timer?.cancel();
    _timer = null;
    final wait = _wait;
    _wait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
  }
}

final class CommandTrackingCancelled implements Exception {
  const CommandTrackingCancelled();
}

/// Bounded polling for an already-created command. Only COMPLETED can indicate
/// conclusion; PENDING/202 or an MQTT publish cannot. With firmware disabled,
/// REJECTED/CAPABILITY_DISABLED is the expected fail-closed outcome.
final class CommandTracker {
  CommandTracker({
    required this._repository,
    CommandScheduler? scheduler,
    DateTime Function()? now,
    Stream<void>? logoutEvents,
    this.pollInterval = const Duration(seconds: 1),
    this.totalLimit = const Duration(seconds: 30),
  }) : // ignore: prefer_initializing_formals
       _scheduler = scheduler ?? TimerCommandScheduler(),
       _now = now ?? DateTime.now {
    _logoutSubscription = logoutEvents?.listen((_) => cancel());
  }

  final CommandRepository _repository;
  final CommandScheduler _scheduler;
  final DateTime Function() _now;
  final Duration pollInterval;
  final Duration totalLimit;
  StreamSubscription<void>? _logoutSubscription;
  final Completer<void> _cancelled = Completer<void>();
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
      final status = await Future.any<CommandStatus>([
        _repository.getCommand(deviceId, commandId),
        _cancelled.future.then<CommandStatus>(
          (_) => throw const CommandTrackingCancelled(),
        ),
      ]);
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
    final scheduler = _scheduler;
    if (scheduler case CancellableCommandScheduler cancellable) {
      cancellable.cancelWaits();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    cancel();
    await _logoutSubscription?.cancel();
  }
}
