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
}
