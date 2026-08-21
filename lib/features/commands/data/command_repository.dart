import '../../../core/network/interbridge_api_client.dart';
import '../domain/command_models.dart';
import 'command_parser.dart';

abstract interface class CommandRepository {
  Future<AcceptedCommand> createOpenDoorCommand(
    DeviceId deviceId,
    String idempotencyKey,
  );

  Future<CommandStatus> getCommand(DeviceId deviceId, CommandId commandId);
}

/// Phase 2D transport. Constructing this repository performs no request and it
/// is intentionally not wired to UI providers yet.
final class HttpCommandRepository implements CommandRepository {
  const HttpCommandRepository(this._api, {this.parser = const CommandParser()});

  final InterBridgeApiClient _api;
  final CommandParser parser;

  @override
  Future<AcceptedCommand> createOpenDoorCommand(
    DeviceId deviceId,
    String idempotencyKey,
  ) async {
    final encoded = Uri.encodeComponent(deviceId.value);
    final json = await _api.post(
      '/v1/devices/$encoded/commands',
      body: const OpenDoorRequest().toJson(),
      headers: {'Idempotency-Key': idempotencyKey},
      expectedStatus: 202,
    );
    return parser.parseAccepted(json);
  }

  @override
  Future<CommandStatus> getCommand(
    DeviceId deviceId,
    CommandId commandId,
  ) async {
    final device = Uri.encodeComponent(deviceId.value);
    final command = Uri.encodeComponent(commandId.value);
    final json = await _api.get('/v1/devices/$device/commands/$command');
    return parser.parseStatus(json);
  }
}
