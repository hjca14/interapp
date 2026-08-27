import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
import 'package:interapp/features/devices/data/parsers/device_notification_preferences_parser.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';

Map<String, dynamic> response({
  Object? updatedAt,
  String alertMode = 'RING_AND_NOTIFICATION',
  int version = 1,
  Map<String, dynamic>? schedule,
}) => {
  'version': version,
  'alert_mode': alertMode,
  'quiet_schedule': schedule ?? {
    'enabled': false,
    'timezone': null,
    'days': <int>[],
    'start_time': null,
    'end_time': null,
    'behavior': 'NOTIFICATION_ONLY',
  },
  'updated_at': updatedAt,
};

void main() {
  const parser = DeviceNotificationPreferencesParser();
  group('domain', () {
    test('four alert modes compose from switches and expose capabilities', () {
      for (final mode in AlertMode.values) {
        expect(
          AlertMode.from(
            ring: mode.includesRing,
            notification: mode.includesNotification,
          ),
          mode,
        );
      }
      expect(AlertMode.none.includesRing, isFalse);
      expect(AlertMode.ringOnly.includesRing, isTrue);
      expect(AlertMode.notificationOnly.includesNotification, isTrue);
      expect(AlertMode.ringAndNotification.includesNotification, isTrue);
    });
    test('defaults, behaviors, equality, copying and overnight interval', () {
      final defaults = DeviceNotificationPreferences();
      expect(defaults.version, 1);
      expect(QuietScheduleBehavior.values, hasLength(2));
      final overnight = QuietSchedule(
        enabled: true,
        timezone: 'America/Sao_Paulo',
        days: const {1, 7},
        startTime: ClockTime(hour: 22, minute: 0),
        endTime: ClockTime(hour: 7, minute: 0),
      );
      expect(overnight.validate(), isNull);
      expect(overnight, overnight.copyWith());
      expect(
        defaults.copyWith(quietSchedule: overnight).quietSchedule.days,
        {1, 7},
      );
    });
  });

  group('strict parser', () {
    test('complete response and nullable/UTC updated_at', () {
      expect(parser.parse(response()).updatedAt, isNull);
      expect(
        parser
            .parse(response(updatedAt: '2026-08-26T12:00:00Z'))
            .updatedAt!
            .isUtc,
        isTrue,
      );
    });
    for (final invalid in [
      response(version: 2),
      response(alertMode: 'NEW_MODE'),
      {...response()}..remove('alert_mode'),
      response(updatedAt: '2026-08-26T12:00:00'),
      response(
        schedule: {
          'enabled': true,
          'timezone': null,
          'days': <int>[],
          'start_time': null,
          'end_time': null,
          'behavior': 'BLOCK_ALL',
        },
      ),
      response(
        schedule: {
          'enabled': true,
          'timezone': 'America/Recife',
          'days': [0],
          'start_time': '22:00',
          'end_time': '07:00',
          'behavior': 'BLOCK_ALL',
        },
      ),
      response(
        schedule: {
          'enabled': true,
          'timezone': 'America/Recife',
          'days': [1, 1],
          'start_time': '22:00',
          'end_time': '07:00',
          'behavior': 'BLOCK_ALL',
        },
      ),
      response(
        schedule: {
          'enabled': true,
          'timezone': 'America/Recife',
          'days': [1],
          'start_time': '25:00',
          'end_time': '07:00',
          'behavior': 'BLOCK_ALL',
        },
      ),
    ]) {
      test('rejects incompatible response $invalid', () {
        expect(() => parser.parse(invalid), throwsA(isA<ApiFailure>()));
      });
    }
  });

  test('minimal and nested PATCH omit technical and unrelated fields', () {
    final baseline = DeviceNotificationPreferences();
    final alertPatch = parser.patch(
      baseline,
      baseline.copyWith(alertMode: AlertMode.none),
    );
    expect(alertPatch, {'alert_mode': 'NONE'});
    final schedulePatch = parser.patch(
      baseline,
      baseline.copyWith(
        quietSchedule: baseline.quietSchedule.copyWith(
          behavior: QuietScheduleBehavior.blockAll,
        ),
      ),
    );
    expect(schedulePatch, {'quiet_schedule': {'behavior': 'BLOCK_ALL'}});
    final text = schedulePatch.toString();
    for (final forbidden in [
      'version',
      'updated_at',
      'user_id',
      'localNetwork',
      'remoteNetwork',
      'confirmBeforeOpeningDoor',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  test('editable equality ignores version and updatedAt', () {
    final baseline = DeviceNotificationPreferences(
      updatedAt: DateTime.utc(2026, 8, 27),
    );
    expect(
      baseline.hasSameEditableValues(baseline.copyWith(version: 2)),
      isTrue,
    );
    expect(
      baseline.hasSameEditableValues(
        baseline.copyWith(updatedAt: DateTime.utc(2026, 8, 28)),
      ),
      isTrue,
    );
    expect(
      baseline.hasSameEditableValues(
        baseline.copyWith(alertMode: AlertMode.none),
      ),
      isFalse,
    );
  });

  test('domain rejects invalid values and protects days from mutation', () {
    expect(
      () => ClockTime(hour: 24, minute: 0),
      throwsArgumentError,
    );
    expect(
      () => QuietSchedule(timezone: ''),
      throwsArgumentError,
    );
    expect(
      () => QuietSchedule(days: const {0}),
      throwsArgumentError,
    );
    final input = <int>{1};
    final schedule = QuietSchedule(days: input);
    input.add(2);
    expect(schedule.days, {1});
    expect(() => schedule.days.add(3), throwsUnsupportedError);
  });

  test('strict parser rejects extra fields and equal active times', () {
    final extraTop = {...response(), 'extra': true};
    final extraNested = response();
    extraNested['quiet_schedule'] = {
      ...(extraNested['quiet_schedule'] as Map<String, dynamic>),
      'extra': true,
    };
    final equalTimes = response(
      schedule: {
        'enabled': true,
        'timezone': 'America/Recife',
        'days': [1],
        'start_time': '22:00',
        'end_time': '22:00',
        'behavior': 'BLOCK_ALL',
      },
    );
    for (final value in [extraTop, extraNested, equalTimes]) {
      expect(() => parser.parse(value), throwsA(isA<ApiFailure>()));
    }
  });
}
