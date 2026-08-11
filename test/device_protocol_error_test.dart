import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

void main() {
  group('DeviceProtocolError.fromWireCode', () {
    const wireValues = {
      'INVALID_PAYLOAD': DeviceProtocolError.invalidPayload,
      'UNSUPPORTED_PROTOCOL_VERSION':
          DeviceProtocolError.unsupportedProtocolVersion,
      'UNKNOWN_COMMAND': DeviceProtocolError.unknownCommand,
      'COMMAND_NOT_ALLOWED': DeviceProtocolError.commandNotAllowed,
      'DEVICE_BUSY': DeviceProtocolError.deviceBusy,
      'NOT_PROVISIONED': DeviceProtocolError.notProvisioned,
      'WIFI_UNAVAILABLE': DeviceProtocolError.wifiUnavailable,
      'CLOUD_UNAVAILABLE': DeviceProtocolError.cloudUnavailable,
      'DOOR_OUTPUT_FAILURE': DeviceProtocolError.doorOutputFailure,
      'OTA_DOWNLOAD_FAILED': DeviceProtocolError.otaDownloadFailed,
      'OTA_VALIDATION_FAILED': DeviceProtocolError.otaValidationFailed,
      'OTA_INSTALL_FAILED': DeviceProtocolError.otaInstallFailed,
      'INTERNAL_ERROR': DeviceProtocolError.internalError,
    };

    wireValues.forEach((wireCode, expected) {
      test('maps $wireCode', () {
        expect(DeviceProtocolError.fromWireCode(wireCode), expected);
      });
    });

    test('maps an unrecognized code to unknown instead of throwing', () {
      expect(
        DeviceProtocolError.fromWireCode('SOME_FUTURE_CODE'),
        DeviceProtocolError.unknown,
      );
    });

    test('maps null to unknown', () {
      expect(
        DeviceProtocolError.fromWireCode(null),
        DeviceProtocolError.unknown,
      );
    });
  });

  group('deviceProtocolErrorMessage', () {
    test('never returns an empty message for any error', () {
      for (final error in DeviceProtocolError.values) {
        expect(deviceProtocolErrorMessage(error), isNotEmpty);
      }
    });

    test('does not leak the wire error code as the user-facing message', () {
      for (final error in DeviceProtocolError.values) {
        expect(deviceProtocolErrorMessage(error), isNot(contains('_')));
      }
    });
  });
}
