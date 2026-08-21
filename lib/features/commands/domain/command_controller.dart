import '../data/command_repository.dart';
import 'command_models.dart';
import 'command_tracker.dart';
import 'idempotency.dart';

/// Internal orchestration seam for a future UI integration.
///
/// [start] represents a new explicit action. [retryCreateAfterTimeout] repeats
/// only the uncertain POST from that same logical action and therefore cannot
/// create a new idempotency key. Neither method is currently called by a
/// widget or provider.
final class CommandController {
  CommandController({
    required CommandRepository repository,
    required CommandTracker tracker,
    required IdempotencyKeyGenerator keyGenerator,
  }) : // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _tracker = tracker,
       _attempt = LogicalCommandAttempt(keyGenerator);

  final CommandRepository _repository;
  final CommandTracker _tracker;
  final LogicalCommandAttempt _attempt;

  DeviceId? _deviceId;

  Future<AcceptedCommand> start(DeviceId deviceId) {
    _deviceId = deviceId;
    return _repository.createOpenDoorCommand(deviceId, _attempt.startNew());
  }

  Future<AcceptedCommand> retryCreateAfterTimeout() {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('Não há tentativa para repetir.');
    }
    return _repository.createOpenDoorCommand(deviceId, _attempt.keyForRetry());
  }

  Future<CommandStatus?> track(AcceptedCommand accepted) {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('Não há tentativa em andamento.');
    }
    return _tracker.track(deviceId, accepted.commandId);
  }

  Future<void> dispose() async {
    _attempt.clear();
    _deviceId = null;
    await _tracker.dispose();
  }
}
