import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/protocol/protocol_constants.dart';

void main() {
  group('protocol version', () {
    test('kProtocolVersion is supported', () {
      expect(isSupportedProtocolVersion(kProtocolVersion), isTrue);
    });

    test('any other version, including null, is unsupported', () {
      expect(isSupportedProtocolVersion(2), isFalse);
      expect(isSupportedProtocolVersion(0), isFalse);
      expect(isSupportedProtocolVersion(null), isFalse);
    });
  });

  group('id generators', () {
    test('generateCommandId uses the cmd- prefix and 32 hex characters', () {
      final id = generateCommandId();
      expect(id, matches(RegExp(r'^cmd-[0-9a-f]{32}$')));
    });

    test('generateEventId uses the evt- prefix and 32 hex characters', () {
      final id = generateEventId();
      expect(id, matches(RegExp(r'^evt-[0-9a-f]{32}$')));
    });

    test('generated ids are not constant', () {
      expect(generateCommandId(), isNot(generateCommandId()));
    });
  });

  group('epoch seconds conversion', () {
    test('dateTimeToEpochSeconds converts a known UTC instant correctly', () {
      final dateTime = DateTime.utc(2026, 8, 11, 17, 30, 25);

      expect(dateTimeToEpochSeconds(dateTime), 1786469425);
    });

    test('dateTimeToEpochSeconds normalizes a local DateTime to UTC first', () {
      final utc = DateTime.utc(2026, 8, 11, 17, 30, 25);
      final asLocal = utc.toLocal();

      expect(dateTimeToEpochSeconds(asLocal), dateTimeToEpochSeconds(utc));
    });

    test('dateTimeToEpochSeconds truncates sub-second precision', () {
      final withMillis = DateTime.utc(2026, 8, 11, 17, 30, 25, 999);
      final withoutMillis = DateTime.utc(2026, 8, 11, 17, 30, 25);

      expect(
        dateTimeToEpochSeconds(withMillis),
        dateTimeToEpochSeconds(withoutMillis),
      );
    });

    test('epochSecondsToDateTime is the inverse of dateTimeToEpochSeconds', () {
      final original = DateTime.utc(2026, 8, 11, 17, 30, 25);

      final roundTripped = epochSecondsToDateTime(
        dateTimeToEpochSeconds(original),
      );

      expect(roundTripped, original);
      expect(roundTripped.isUtc, isTrue);
    });

    test('epochSecondsToDateTime always returns a UTC DateTime', () {
      expect(epochSecondsToDateTime(0).isUtc, isTrue);
    });
  });
}
