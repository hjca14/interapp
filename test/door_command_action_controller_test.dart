import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/commands/data/command_repository.dart';
import 'package:interapp/features/commands/domain/command_controller.dart';
import 'package:interapp/features/commands/domain/command_models.dart';
import 'package:interapp/features/commands/domain/command_tracker.dart';
import 'package:interapp/features/commands/domain/idempotency.dart';
import 'package:interapp/features/commands/presentation/providers/door_command_provider.dart';

const _device = 'ib-0123456789abcdef0123456789abcdef';
const _command = '0123456789abcdef0123456789abcdef';

void main() {
  test('PENDING waits and a double tap creates exactly one command', () async {
    final create = Completer<AcceptedCommand>();
    final status = Completer<CommandStatus>();
    final repository = _FakeRepository(
      createCompleter: create,
      statusCompleter: status,
    );
    final action = _action(repository);

    final first = action.start();
    final second = action.start();
    expect(action.state.phase, DoorCommandPhase.sending);
    expect(repository.createCalls, 1);

    create.complete(_accepted());
    await Future<void>.delayed(Duration.zero);
    expect(action.state.phase, DoorCommandPhase.waiting);
    status.complete(_status(CommandState.completed));
    await Future.wait([first, second]);
    expect(action.state.message, 'Abertura confirmada pelo dispositivo.');
  });

  test('only COMPLETED reports confirmed opening', () async {
    for (final status in [
      _status(CommandState.rejected, 'OTHER_SAFE_CODE'),
      _status(CommandState.expired),
    ]) {
      final repository = _FakeRepository(status: status);
      final action = _action(repository);
      await action.start();
      expect(action.state.message, isNot(contains('Abertura confirmada')));
    }
  });

  test(
    'CAPABILITY_DISABLED has the expected friendly fail-closed text',
    () async {
      final action = _action(
        _FakeRepository(
          status: _status(CommandState.rejected, 'CAPABILITY_DISABLED'),
        ),
      );
      await action.start();
      expect(
        action.state.message,
        contains('A abertura ainda não está configurada neste dispositivo.'),
      );
      expect(
        action.state.message,
        contains('Nenhuma ação física foi realizada.'),
      );
    },
  );

  test(
    'tracking limit and EXPIRED use the same unknown-result message',
    () async {
      final clock = _Clock();
      final repository = _FakeRepository(status: _status(CommandState.pending));
      final action = _action(
        repository,
        scheduler: _AdvancingScheduler(clock),
        now: clock.now,
        totalLimit: const Duration(seconds: 2),
      );
      await action.start();
      expect(action.state.phase, DoorCommandPhase.timedOut);
      expect(
        action.state.message,
        'O dispositivo não confirmou a solicitação a tempo.',
      );
    },
  );

  test('ambiguous create timeout offers retry with the same key', () async {
    final repository = _FakeRepository(
      createErrors: [const ApiFailure(ApiFailureKind.timeout, 'safe timeout')],
      status: _status(CommandState.completed),
    );
    final keys = _Keys();
    final action = _action(repository, keys: keys);

    await action.start();
    expect(action.state.canRetryCreate, isTrue);
    await action.retryCreateAfterTimeout();
    expect(repository.keys, ['key-1', 'key-1']);
    expect(action.state.phase, DoorCommandPhase.completed);

    await action.start();
    expect(repository.keys.last, 'key-2');
  });

  for (final failure in [
    const ApiFailure(ApiFailureKind.forbidden, 'Sem permissão.'),
    const ApiFailure(ApiFailureKind.offline, 'Sem conexão.'),
    const ApiFailure(ApiFailureKind.server, 'Erro no serviço.'),
    const ApiFailure(ApiFailureKind.unavailable, 'Serviço indisponível.'),
    const ApiFailure(ApiFailureKind.unauthorized, 'Sessão expirada.'),
  ]) {
    test('shows sanitized ${failure.kind.name} create failure', () async {
      final action = _action(_FakeRepository(createErrors: [failure]));
      await action.start();
      expect(action.state.phase, DoorCommandPhase.failed);
      expect(action.state.message, failure.message);
    });
  }

  test('cancel/dispose ends held polling without a UI failure', () async {
    final repository = _FakeRepository(
      statusCompleter: Completer<CommandStatus>(),
    );
    final action = _action(repository, scheduler: _HeldScheduler());
    final running = action.start();
    await Future<void>.delayed(Duration.zero);
    action.cancel();
    await running;
    expect(action.state.phase, DoorCommandPhase.waiting);
    action.dispose();
  });
}

DoorCommandActionController _action(
  _FakeRepository repository, {
  IdempotencyKeyGenerator? keys,
  CommandScheduler scheduler = const _ImmediateScheduler(),
  DateTime Function()? now,
  Duration totalLimit = const Duration(seconds: 30),
}) {
  return DoorCommandActionController(
    deviceId: _device,
    controller: CommandController(
      repository: repository,
      tracker: CommandTracker(
        repository: repository,
        scheduler: scheduler,
        now: now,
        totalLimit: totalLimit,
      ),
      keyGenerator: keys ?? _Keys(),
    ),
  );
}

AcceptedCommand _accepted() => AcceptedCommand(
  commandId: CommandId(_command),
  issuedAt: UtcTimestamp.parse('2026-08-22T12:00:00Z'),
  expiresAt: UtcTimestamp.parse('2026-08-22T12:00:30Z'),
);

CommandStatus _status(CommandState state, [String? code]) => CommandStatus(
  commandId: CommandId(_command),
  state: state,
  rejection: code == null ? null : CommandRejection(code),
);

class _FakeRepository implements CommandRepository {
  _FakeRepository({
    this.createCompleter,
    this.statusCompleter,
    this.status,
    this.createErrors = const [],
  });

  final Completer<AcceptedCommand>? createCompleter;
  final Completer<CommandStatus>? statusCompleter;
  final CommandStatus? status;
  final List<ApiFailure> createErrors;
  final List<String> keys = [];
  int createCalls = 0;

  @override
  Future<AcceptedCommand> createOpenDoorCommand(DeviceId deviceId, String key) {
    keys.add(key);
    final index = createCalls++;
    if (index < createErrors.length) return Future.error(createErrors[index]);
    return createCompleter?.future ?? Future.value(_accepted());
  }

  @override
  Future<CommandStatus> getCommand(DeviceId deviceId, CommandId commandId) {
    return statusCompleter?.future ?? Future.value(status!);
  }
}

class _Keys implements IdempotencyKeyGenerator {
  int count = 0;
  @override
  String generate() => 'key-${++count}';
}

class _Clock {
  DateTime value = DateTime.utc(2026, 8, 22);
  DateTime now() => value;
}

class _AdvancingScheduler implements CommandScheduler {
  _AdvancingScheduler(this.clock);
  final _Clock clock;
  @override
  Future<void> wait(Duration duration) async =>
      clock.value = clock.value.add(duration);
}

class _ImmediateScheduler implements CommandScheduler {
  const _ImmediateScheduler();
  @override
  Future<void> wait(Duration duration) async {}
}

class _HeldScheduler implements CommandScheduler {
  @override
  Future<void> wait(Duration duration) => Completer<void>().future;
}
