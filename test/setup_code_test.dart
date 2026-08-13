import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';

void main() {
  group('SetupCode.tryParse', () {
    test('accepts a plain 12-digit code', () {
      final code = SetupCode.tryParse('482719362051');
      expect(code, isNotNull);
      expect(code!.value, '482719362051');
    });

    test('normalizes a space-separated code', () {
      final code = SetupCode.tryParse('4827 1936 2051');
      expect(code, isNotNull);
      expect(code!.value, '482719362051');
    });

    test('normalizes a dash-separated code', () {
      final code = SetupCode.tryParse('4827-1936-2051');
      expect(code, isNotNull);
      expect(code!.value, '482719362051');
    });

    test('rejects a code that is too short', () {
      expect(SetupCode.tryParse('48271936205'), isNull);
    });

    test('rejects a code that is too long', () {
      expect(SetupCode.tryParse('4827193620512'), isNull);
    });

    test('rejects non-digit characters', () {
      expect(SetupCode.tryParse('4827a936205b'), isNull);
    });

    test('rejects an empty string', () {
      expect(SetupCode.tryParse(''), isNull);
    });

    test('never throws for arbitrary input', () {
      expect(() => SetupCode.tryParse('###garbage###'), returnsNormally);
    });
  });

  group('SetupCode.maskedForLogging', () {
    test('shows only the last 4 digits', () {
      final code = SetupCode.tryParse('482719362051')!;
      expect(code.maskedForLogging, '••••••••2051');
    });

    test('the masked form never contains the full code', () {
      final code = SetupCode.tryParse('482719362051')!;
      expect(code.maskedForLogging, isNot(contains('482719362051')));
    });
  });

  group('SetupCode.toString', () {
    test('shows the plain value (this is user-visible input, not a secret to hide in the UI)', () {
      final code = SetupCode.tryParse('482719362051')!;
      expect(code.toString(), '482719362051');
    });
  });

  group('parseSetupCodeQrPayload', () {
    test('parses a valid payload', () {
      final code = parseSetupCodeQrPayload('{"version": 1, "setup_code": "482719362051"}');
      expect(code, isNotNull);
      expect(code!.value, '482719362051');
    });

    test('ignores an optional device_id field', () {
      final code = parseSetupCodeQrPayload(
        '{"version": 1, "setup_code": "482719362051", "device_id": "ib-abc"}',
      );
      expect(code, isNotNull);
    });

    test('rejects a version other than 1', () {
      expect(parseSetupCodeQrPayload('{"version": 2, "setup_code": "482719362051"}'), isNull);
    });

    test('rejects a missing setup_code', () {
      expect(parseSetupCodeQrPayload('{"version": 1}'), isNull);
    });

    test('rejects an invalid setup_code inside an otherwise valid payload', () {
      expect(parseSetupCodeQrPayload('{"version": 1, "setup_code": "not-digits"}'), isNull);
    });

    test('rejects malformed JSON instead of throwing', () {
      expect(() => parseSetupCodeQrPayload('not json'), returnsNormally);
      expect(parseSetupCodeQrPayload('not json'), isNull);
    });

    test('rejects a JSON value that is not an object', () {
      expect(parseSetupCodeQrPayload('[1, 2, 3]'), isNull);
    });
  });
}
