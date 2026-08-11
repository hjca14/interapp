import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_command.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

void main() {
  group('DeviceCommandType', () {
    test('OPEN_DOOR and RESTART round-trip through the wire value', () {
      expect(
        DeviceCommandType.fromWireValue('OPEN_DOOR'),
        DeviceCommandType.openDoor,
      );
      expect(DeviceCommandType.openDoor.wireValue, 'OPEN_DOOR');
      expect(
        DeviceCommandType.fromWireValue('RESTART'),
        DeviceCommandType.restart,
      );
      expect(DeviceCommandType.restart.wireValue, 'RESTART');
    });

    test(
      'reserved future commands still parse, so a result referencing one does not crash',
      () {
        expect(
          DeviceCommandType.fromWireValue('ANSWER_CALL'),
          DeviceCommandType.answerCall,
        );
        expect(
          DeviceCommandType.fromWireValue('REJECT_CALL'),
          DeviceCommandType.rejectCall,
        );
        expect(
          DeviceCommandType.fromWireValue('END_CALL'),
          DeviceCommandType.endCall,
        );
      },
    );

    test('an unrecognized command name becomes unknown', () {
      expect(
        DeviceCommandType.fromWireValue('SOME_FUTURE_COMMAND'),
        DeviceCommandType.unknown,
      );
      expect(DeviceCommandType.fromWireValue(null), DeviceCommandType.unknown);
    });
  });

  group('DeviceCommandStatus', () {
    test('only accepted is non-terminal', () {
      expect(DeviceCommandStatus.accepted.isTerminal, isFalse);
      expect(DeviceCommandStatus.completed.isTerminal, isTrue);
      expect(DeviceCommandStatus.failed.isTerminal, isTrue);
      expect(DeviceCommandStatus.rejected.isTerminal, isTrue);
      expect(DeviceCommandStatus.timedOut.isTerminal, isTrue);
    });
  });

  group('DeviceCommandResult', () {
    test('carries the command, status and optional error', () {
      const result = DeviceCommandResult(
        commandId: 'cmd-abc',
        command: DeviceCommandType.openDoor,
        status: DeviceCommandStatus.failed,
        error: DeviceProtocolError.doorOutputFailure,
      );

      expect(result.commandId, 'cmd-abc');
      expect(result.command, DeviceCommandType.openDoor);
      expect(result.status, DeviceCommandStatus.failed);
      expect(result.error, DeviceProtocolError.doorOutputFailure);
    });

    test('error is optional for a successful result', () {
      const result = DeviceCommandResult(
        commandId: 'cmd-abc',
        command: DeviceCommandType.openDoor,
        status: DeviceCommandStatus.completed,
      );

      expect(result.error, isNull);
    });
  });
}
