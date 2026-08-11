import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';

void main() {
  group('DeviceClaim.toString', () {
    test('redacts the claim code', () {
      const claim = DeviceClaim(
        deviceId: 'ib-abc123',
        claimCode: 'super-secret-value',
      );

      final text = claim.toString();

      expect(text, contains('ib-abc123'));
      expect(text, isNot(contains('super-secret-value')));
    });
  });

  group('parseDeviceClaimQrPayload', () {
    test('parses a valid device_id + claim_code payload', () {
      final claim = parseDeviceClaimQrPayload(
        '{"device_id": "ib-abc123", "claim_code": "secret-code"}',
      );

      expect(claim, isNotNull);
      expect(claim!.deviceId, 'ib-abc123');
      expect(claim.claimCode, 'secret-code');
    });

    test('rejects payloads missing device_id', () {
      expect(
        parseDeviceClaimQrPayload('{"claim_code": "secret-code"}'),
        isNull,
      );
    });

    test('rejects payloads missing claim_code', () {
      expect(parseDeviceClaimQrPayload('{"device_id": "ib-abc123"}'), isNull);
    });

    test('rejects payloads with an empty device_id or claim_code', () {
      expect(
        parseDeviceClaimQrPayload(
          '{"device_id": "", "claim_code": "secret-code"}',
        ),
        isNull,
      );
      expect(
        parseDeviceClaimQrPayload(
          '{"device_id": "ib-abc123", "claim_code": ""}',
        ),
        isNull,
      );
    });

    test('rejects malformed JSON instead of throwing', () {
      expect(parseDeviceClaimQrPayload('not json at all'), isNull);
    });

    test('rejects a JSON value that is not an object', () {
      expect(parseDeviceClaimQrPayload('[1, 2, 3]'), isNull);
      expect(parseDeviceClaimQrPayload('"just a string"'), isNull);
    });
  });
}
