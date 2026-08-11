import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/domain/entities/intercom_state.dart';

void main() {
  group('IntercomState.fromRaw', () {
    const knownWireValues = {
      'IDLE': IntercomState.idle,
      'RINGING': IntercomState.ringing,
      'OFF_HOOK': IntercomState.offHook,
      'IN_CALL': IntercomState.inCall,
      'ERROR': IntercomState.error,
    };

    knownWireValues.forEach((wireValue, expected) {
      test('recognizes $wireValue', () {
        final state = IntercomState.fromRaw(wireValue);
        expect(state, expected);
        expect(state.isKnown, isTrue);
        expect(state.raw, wireValue);
      });
    });

    test('null becomes the unreported sentinel', () {
      final state = IntercomState.fromRaw(null);
      expect(state, IntercomState.unreported);
      expect(state.isReported, isFalse);
      expect(state.isKnown, isFalse);
    });

    test('an unrecognized value becomes a safe unknown state, not an exception', () {
      expect(() => IntercomState.fromRaw('SOME_FUTURE_STATE'), returnsNormally);

      final state = IntercomState.fromRaw('SOME_FUTURE_STATE');

      expect(state.isKnown, isFalse);
      expect(state.isReported, isTrue);
      // The raw value is preserved for diagnostics even though it's unknown.
      expect(state.raw, 'SOME_FUTURE_STATE');
    });

    test('unknown values are distinct from every known state', () {
      final state = IntercomState.fromRaw('SOME_FUTURE_STATE');

      expect(state, isNot(IntercomState.idle));
      expect(state, isNot(IntercomState.ringing));
      expect(state, isNot(IntercomState.offHook));
      expect(state, isNot(IntercomState.inCall));
      expect(state, isNot(IntercomState.error));
    });
  });

  group('IntercomState equality', () {
    test('two states parsed from the same raw value are equal', () {
      expect(IntercomState.fromRaw('RINGING'), IntercomState.fromRaw('RINGING'));
    });

    test('toString exposes the raw value', () {
      expect(IntercomState.idle.toString(), 'IDLE');
      expect(IntercomState.unreported.toString(), 'unreported');
    });
  });
}
