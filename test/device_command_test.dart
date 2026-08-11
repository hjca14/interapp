import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/protocol/protocol_constants.dart';
import 'package:interapp/features/devices/domain/entities/device_command.dart';

void main() {
  group('DeviceCommand.toJson', () {
    test('encodes issued_at/expires_at as Unix epoch seconds, not ISO-8601', () {
      final command = DeviceCommand(
        commandId: 'cmd-abc123',
        command: DeviceCommandType.openDoor,
        issuedAt: DateTime.utc(2026, 8, 11, 17, 30, 25),
        expiresAt: DateTime.utc(2026, 8, 11, 17, 30, 30),
      );

      final json = command.toJson();

      expect(json['protocol_version'], kProtocolVersion);
      expect(json['command_id'], 'cmd-abc123');
      expect(json['command'], 'OPEN_DOOR');
      expect(json['issued_at'], isA<int>());
      expect(json['issued_at'], 1786469425);
      expect(json['expires_at'], 1786469430);
    });

    test('omits payload when null and includes it when present', () {
      final withoutPayload = DeviceCommand(
        commandId: 'cmd-1',
        command: DeviceCommandType.restart,
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 1, 0, 1),
      );
      final withPayload = DeviceCommand(
        commandId: 'cmd-2',
        command: DeviceCommandType.restart,
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 1, 0, 1),
        payload: const {'reason': 'test'},
      );

      expect(withoutPayload.toJson().containsKey('payload'), isFalse);
      expect(withPayload.toJson()['payload'], {'reason': 'test'});
    });
  });

  group('DeviceCommand.fromJson', () {
    test('round-trips through toJson', () {
      final original = DeviceCommand(
        commandId: 'cmd-abc123',
        command: DeviceCommandType.openDoor,
        issuedAt: DateTime.utc(2026, 8, 11, 17, 30, 25),
        expiresAt: DateTime.utc(2026, 8, 11, 17, 30, 30),
      );

      final decoded = DeviceCommand.fromJson(original.toJson());

      expect(decoded.commandId, original.commandId);
      expect(decoded.command, original.command);
      expect(decoded.issuedAt, original.issuedAt);
      expect(decoded.expiresAt, original.expiresAt);
      expect(decoded.issuedAt.isUtc, isTrue);
    });

    test('throws UnsupportedProtocolVersionException for a future protocol version', () {
      expect(
        () => DeviceCommand.fromJson(const {
          'protocol_version': 2,
          'command_id': 'cmd-1',
          'command': 'OPEN_DOOR',
          'issued_at': 1786469425,
          'expires_at': 1786469430,
        }),
        throwsA(isA<UnsupportedProtocolVersionException>()),
      );
    });

    test('an unrecognized command name becomes unknown instead of throwing', () {
      final decoded = DeviceCommand.fromJson(const {
        'protocol_version': 1,
        'command_id': 'cmd-1',
        'command': 'SOME_FUTURE_COMMAND',
        'issued_at': 1786469425,
        'expires_at': 1786469430,
      });

      expect(decoded.command, DeviceCommandType.unknown);
    });
  });
}
