import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';

void main() {
  const validDeviceId = 'ib-7f3a91c2d84e4fa9b621b88658fdca77';

  group('DeviceClaim.toString', () {
    test('redacts the claim code', () {
      const claim = DeviceClaim(
        deviceId: validDeviceId,
        claimCode: 'super-secret-value',
      );

      final text = claim.toString();

      expect(text, contains(validDeviceId));
      expect(text, isNot(contains('super-secret-value')));
    });
  });

  group('parseDeviceClaimQrPayload', () {
    test('parses a valid interbridge://claim URI', () {
      final claim = parseDeviceClaimQrPayload(
        'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=secret-code',
      );

      expect(claim, isNotNull);
      expect(claim!.deviceId, validDeviceId);
      expect(claim.claimCode, 'secret-code');
    });

    test('decodes percent-encoded claim_code values', () {
      final claim = parseDeviceClaimQrPayload(
        'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=a%20b%2Fc',
      );

      expect(claim, isNotNull);
      expect(claim!.claimCode, 'a b/c');
    });

    test('rejects a scheme other than interbridge', () {
      expect(
        parseDeviceClaimQrPayload(
          'https://claim?v=1&device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
    });

    test('rejects a host other than claim', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://pair?v=1&device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
    });

    test('rejects a version other than 1', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=2&device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
    });

    test('rejects a missing version', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
    });

    test('rejects a malformed device_id', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=not-a-device-id&claim_code=secret',
        ),
        isNull,
      );
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=ib-TOOSHORT&claim_code=secret',
        ),
        isNull,
      );
      expect(
        // Uppercase hex is rejected — the contract requires lowercase.
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=IB-7F3A91C2D84E4FA9B621B88658FDCA77&claim_code=secret',
        ),
        isNull,
      );
    });

    test('rejects a missing or empty claim_code', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=$validDeviceId',
        ),
        isNull,
      );
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=',
        ),
        isNull,
      );
    });

    test('rejects duplicate required query parameters', () {
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&v=1&device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=$validDeviceId&device_id=$validDeviceId&claim_code=secret',
        ),
        isNull,
      );
      expect(
        parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=secret&claim_code=other',
        ),
        isNull,
      );
    });

    test('rejects a malformed/empty URI instead of throwing', () {
      expect(
        () => parseDeviceClaimQrPayload('not a uri at all: ###'),
        returnsNormally,
      );
      expect(parseDeviceClaimQrPayload('not a uri at all: ###'), isNull);
      expect(parseDeviceClaimQrPayload(''), isNull);
    });

    test(
      'rejects an invalid percent-encoded UTF-8 sequence instead of throwing',
      () {
        // %FF alone is not a valid UTF-8 byte sequence — Dart's Uri decoder
        // throws FormatException for this (unlike a merely non-hex escape,
        // see the test below), which parseDeviceClaimQrPayload must catch.
        const malformed =
            'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=%FF';

        expect(() => parseDeviceClaimQrPayload(malformed), returnsNormally);
        expect(parseDeviceClaimQrPayload(malformed), isNull);
      },
    );

    test(
      'a non-hex escape is passed through literally rather than crashing',
      () {
        // '%zz' isn't valid percent-encoding, but Dart's Uri leaves such
        // sequences as literal text instead of throwing — still safe (no
        // exception), just not a "rejection" the way invalid UTF-8 is.
        final claim = parseDeviceClaimQrPayload(
          'interbridge://claim?v=1&device_id=$validDeviceId&claim_code=bad%zz',
        );

        expect(claim, isNotNull);
        expect(claim!.claimCode, 'bad%zz');
      },
    );

    test(
      'never throws, for any input — so a secret can never leak via an exception message',
      () {
        const secret = 'super-secret-value';
        expect(
          () => parseDeviceClaimQrPayload('garbage-$secret'),
          returnsNormally,
        );
        expect(() => parseDeviceClaimQrPayload(secret), returnsNormally);
      },
    );
  });
}
