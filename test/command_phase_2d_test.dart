import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:interapp/features/commands/data/command_parser.dart';
import 'package:interapp/features/commands/data/command_repository.dart';
import 'package:interapp/features/commands/domain/command_models.dart';
import 'package:interapp/features/commands/domain/command_tracker.dart';
import 'package:interapp/features/commands/domain/idempotency.dart';

const device = 'ib-0123456789abcdef0123456789abcdef';
const command = '0123456789abcdef0123456789abcdef';
const acceptedJson = <String, dynamic>{
  'command_id': command,
  'state': 'PENDING',
  'issued_at': '2026-08-21T12:00:00Z',
  'expires_at': '2026-08-21T12:00:30Z',
};

void main() {
  group('HTTP command transport', () {
    test('sends exact POST, empty parameters and idempotency header', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/devices/$device/commands');
        expect(request.headers['authorization'], 'Bearer access-secret');
        expect(request.headers['idempotency-key'], 'opaque-secret');
        expect(jsonDecode(request.body), {
          'command': 'OPEN_DOOR',
          'parameters': <String, dynamic>{},
        });
        return http.Response(jsonEncode(acceptedJson), 202);
      });
      final repository = _repository(client);
      final result = await repository.createOpenDoorCommand(
        DeviceId(device),
        'opaque-secret',
      );
      expect(result.state, CommandState.pending);
    });

    for (final entry in <int, ApiFailureKind>{
      400: ApiFailureKind.badRequest,
      403: ApiFailureKind.forbidden,
      404: ApiFailureKind.notFound,
      409: ApiFailureKind.conflict,
      429: ApiFailureKind.rateLimited,
      500: ApiFailureKind.server,
      503: ApiFailureKind.unavailable,
    }.entries) {
      test('maps ${entry.key} safely', () async {
        final repository = _repository(
          MockClient((_) async => http.Response('backend secret', entry.key)),
        );
        await expectLater(
          repository.createOpenDoorCommand(DeviceId(device), 'key'),
          throwsA(
            isA<ApiFailure>().having((error) => error.kind, 'kind', entry.value),
          ),
        );
      });
    }

    test('401 refreshes once then invalidates the existing session', () async {
      final auth = _Auth();
      final repository = _repository(
        MockClient((_) async => http.Response('', 401)),
        auth: auth,
      );
      await expectLater(
        repository.createOpenDoorCommand(DeviceId(device), 'key'),
        throwsA(isA<ApiFailure>()),
      );
      expect(auth.forcedRefreshes, 1);
      expect(auth.invalidated, isTrue);
    });

    for (final entry in <String?, Duration?>{
      '5': const Duration(seconds: 5),
      null: null,
      '-1': null,
      '999': const Duration(seconds: 30),
    }.entries) {
      test('bounds Retry-After ${entry.key}', () async {
        final repository = _repository(
          MockClient(
            (_) async => http.Response(
              '',
              429,
              headers: {'retry-after': ?entry.key},
            ),
          ),
        );
        try {
          await repository.createOpenDoorCommand(DeviceId(device), 'key');
          fail('expected failure');
        } on ApiFailure catch (error) {
          expect(error.retryAfter, entry.value);
        }
      });
    }

    test('maps timeout to existing connectivity failure', () async {
      final api = InterBridgeApiClient(
        baseUrl: 'https://api.example.invalid',
        auth: _Auth(),
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: Duration.zero,
      );
      await expectLater(
        HttpCommandRepository(api).createOpenDoorCommand(
          DeviceId(device),
          'key',
        ),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );
    });

    test('maps offline client failure', () async {
      final repository = _repository(
        MockClient((_) async => throw http.ClientException('SDK secret')),
      );
      await expectLater(
        repository.createOpenDoorCommand(DeviceId(device), 'key'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.offline,
          ),
        ),
      );
    });

    test('invalid JSON becomes invalidResponse without raw response', () async {
      final repository = _repository(
        MockClient((_) async => http.Response('raw secret {', 202)),
      );
      await expectLater(
        repository.createOpenDoorCommand(DeviceId(device), 'key'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (error) => error.kind,
                'kind',
                ApiFailureKind.invalidResponse,
              )
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('raw secret')),
              ),
        ),
      );
    });
  });

  group('pure parsing', () {
    const parser = CommandParser();

    test('parses PENDING accepted response and UTC timestamps', () {
      final value = parser.parseAccepted(acceptedJson);
      expect(value.commandId.value, command);
      expect(value.issuedAt.value.isUtc, isTrue);
    });

    for (final state in ['COMPLETED', 'EXPIRED']) {
      test('parses $state', () {
        final value = parser.parseStatus({
          'command_id': command,
          'state': state,
        });
        expect(value.isTerminal, isTrue);
      });
    }

    for (final code in ['CAPABILITY_DISABLED', 'NOT_CONFIGURED']) {
      test('parses REJECTED/$code', () {
        final value = parser.parseStatus({
          'command_id': command,
          'state': 'REJECTED',
          'rejection': {'code': code},
        });
        expect(value.rejection?.code, code);
      });
    }

    for (final malformed in <Map<String, dynamic>>[
      {...acceptedJson, 'command_id': 'ABC'},
      {...acceptedJson, 'issued_at': '2026-08-21T12:00:00'},
      {...acceptedJson, 'state': 'ACCEPTED'},
      {...acceptedJson}..remove('expires_at'),
    ]) {
      test('malformed response is typed invalidResponse', () {
        expect(
          () => parser.parseAccepted(malformed),
          throwsA(
            isA<ApiFailure>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.invalidResponse,
            ),
          ),
        );
      });
    }
  });

  test('logical retry reuses a key and explicit action creates another', () {
    final generator = _Keys();
    final attempt = LogicalCommandAttempt(generator);
    expect(attempt.keyForRetry(), 'opaque-1');
    expect(attempt.keyForRetry(), 'opaque-1');
    expect(attempt.startNew(), 'opaque-2');
  });

  group('bounded polling without real waits', () {
    test('terminates at terminal state', () async {
      final clock = _Clock();
      final repository = _CommandRepository([
        _status(CommandState.pending),
        _status(CommandState.completed),
      ]);
      final tracker = CommandTracker(
        repository: repository,
        scheduler: _AdvancingScheduler(clock),
        now: clock.now,
      );
      expect(
        (await tracker.track(DeviceId(device), CommandId(command)))?.state,
        CommandState.completed,
      );
      expect(repository.calls, 2);
    });

    test('terminates at total limit', () async {
      final clock = _Clock();
      final repository = _CommandRepository([_status(CommandState.pending)]);
      final tracker = CommandTracker(
        repository: repository,
        scheduler: _AdvancingScheduler(clock),
        now: clock.now,
        totalLimit: const Duration(seconds: 3),
      );
      expect(await tracker.track(DeviceId(device), CommandId(command)), isNull);
      expect(repository.calls, 3);
    });

    test('explicit cancel and logout cancel polling', () async {
      for (final logout in [false, true]) {
        final events = StreamController<void>();
        final scheduler = _HeldScheduler();
        final tracker = CommandTracker(
          repository: _CommandRepository([_status(CommandState.pending)]),
          scheduler: scheduler,
          logoutEvents: events.stream,
        );
        final future = tracker.track(DeviceId(device), CommandId(command));
        if (logout) {
          events.add(null);
        } else {
          tracker.cancel();
        }
        await expectLater(future, throwsA(isA<CommandTrackingCancelled>()));
        await events.close();
      }
    });
  });
}

HttpCommandRepository _repository(http.Client client, {_Auth? auth}) {
  return HttpCommandRepository(
    InterBridgeApiClient(
      baseUrl: 'https://api.example.invalid',
      auth: auth ?? _Auth(),
      client: client,
    ),
  );
}

CommandStatus _status(CommandState state) => CommandStatus(
  commandId: CommandId(command),
  state: state,
  rejection: state == CommandState.rejected
      ? const CommandRejection('CAPABILITY_DISABLED')
      : null,
);

final class _Auth implements AuthRepository {
  int forcedRefreshes = 0;
  bool invalidated = false;

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    if (forceRefresh) forcedRefreshes++;
    return 'access-secret';
  }

  @override
  Future<void> invalidateSession() async => invalidated = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Keys implements IdempotencyKeyGenerator {
  int count = 0;
  @override
  String generate() => 'opaque-${++count}';
}

final class _CommandRepository implements CommandRepository {
  _CommandRepository(this.responses);
  final List<CommandStatus> responses;
  int calls = 0;

  @override
  Future<CommandStatus> getCommand(DeviceId deviceId, CommandId commandId) async {
    final index = calls++;
    final boundedIndex = index < responses.length ? index : responses.length - 1;
    return responses[boundedIndex];
  }

  @override
  Future<AcceptedCommand> createOpenDoorCommand(
    DeviceId deviceId,
    String idempotencyKey,
  ) => throw UnimplementedError();
}

final class _Clock {
  DateTime value = DateTime.utc(2026, 8, 21);
  DateTime now() => value;
}

final class _AdvancingScheduler implements CommandScheduler {
  _AdvancingScheduler(this.clock);
  final _Clock clock;
  @override
  Future<void> wait(Duration duration) async {
    clock.value = clock.value.add(duration);
  }
}

final class _HeldScheduler implements CommandScheduler {
  @override
  Future<void> wait(Duration duration) => Completer<void>().future;
}
