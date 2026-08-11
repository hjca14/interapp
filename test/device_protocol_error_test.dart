import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';

void main() {
  group('DeviceProtocolError.fromWireCode', () {
    const wireValues = {
      'INVALID_PAYLOAD': DeviceProtocolError.invalidPayload,
      'PAYLOAD_TOO_LARGE': DeviceProtocolError.payloadTooLarge,
      'UNSUPPORTED_PROTOCOL_VERSION':
          DeviceProtocolError.unsupportedProtocolVersion,
      'UNKNOWN_COMMAND': DeviceProtocolError.unknownCommand,
      'COMMAND_NOT_ALLOWED': DeviceProtocolError.commandNotAllowed,
      'COMMAND_EXPIRED': DeviceProtocolError.commandExpired,
      'CLOCK_NOT_TRUSTWORTHY': DeviceProtocolError.clockNotTrustworthy,
      'INVALID_TIMESTAMP': DeviceProtocolError.invalidTimestamp,
      'DEVICE_BUSY': DeviceProtocolError.deviceBusy,
      'NOT_PROVISIONED': DeviceProtocolError.notProvisioned,
      'WIFI_UNAVAILABLE': DeviceProtocolError.wifiUnavailable,
      'CLOUD_UNAVAILABLE': DeviceProtocolError.cloudUnavailable,
      'DOOR_OUTPUT_FAILURE': DeviceProtocolError.doorOutputFailure,
      'OTA_DOWNLOAD_FAILED': DeviceProtocolError.otaDownloadFailed,
      'OTA_VALIDATION_FAILED': DeviceProtocolError.otaValidationFailed,
      'OTA_INSTALL_FAILED': DeviceProtocolError.otaInstallFailed,
      'PROVISIONING_FAILED': DeviceProtocolError.provisioningFailed,
      'INTERNAL_ERROR': DeviceProtocolError.internalError,
    };

    test('covers every code in the wire vocabulary exactly once', () {
      // Every DeviceProtocolError value except `unknown` must have exactly
      // one wire code mapped to it above — this fails loudly if a new value
      // is added to the enum without a corresponding test case.
      final coveredValues = wireValues.values.toSet();
      final expectedValues = DeviceProtocolError.values
          .where((error) => error != DeviceProtocolError.unknown)
          .toSet();
      expect(coveredValues, expectedValues);
    });

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

  group('DeviceProtocolError.origin', () {
    test('classifies device-reported errors as device', () {
      const deviceErrors = {
        DeviceProtocolError.invalidPayload,
        DeviceProtocolError.payloadTooLarge,
        DeviceProtocolError.unsupportedProtocolVersion,
        DeviceProtocolError.unknownCommand,
        DeviceProtocolError.commandNotAllowed,
        DeviceProtocolError.commandExpired,
        DeviceProtocolError.clockNotTrustworthy,
        DeviceProtocolError.invalidTimestamp,
        DeviceProtocolError.deviceBusy,
        DeviceProtocolError.notProvisioned,
        DeviceProtocolError.wifiUnavailable,
        DeviceProtocolError.doorOutputFailure,
        DeviceProtocolError.otaDownloadFailed,
        DeviceProtocolError.otaValidationFailed,
        DeviceProtocolError.otaInstallFailed,
        DeviceProtocolError.provisioningFailed,
      };
      for (final error in deviceErrors) {
        expect(
          error.origin,
          DeviceProtocolErrorOrigin.device,
          reason: '$error should be classified as device',
        );
      }
    });

    test('classifies cloudUnavailable as connectivity', () {
      expect(
        DeviceProtocolError.cloudUnavailable.origin,
        DeviceProtocolErrorOrigin.connectivity,
      );
    });

    test('classifies internalError and unknown as backend', () {
      expect(
        DeviceProtocolError.internalError.origin,
        DeviceProtocolErrorOrigin.backend,
      );
      expect(
        DeviceProtocolError.unknown.origin,
        DeviceProtocolErrorOrigin.backend,
      );
    });

    test('every error has exactly one origin', () {
      for (final error in DeviceProtocolError.values) {
        expect(() => error.origin, returnsNormally);
      }
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
