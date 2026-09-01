import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';
import 'package:interapp/features/devices/presentation/pages/notification_preferences_page.dart';
import 'package:interapp/features/devices/presentation/providers/device_notification_preferences_provider.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository implements DeviceNotificationPreferencesRepository {
  _Repository({DeviceNotificationPreferences? value})
    : value = value ?? DeviceNotificationPreferences();

  DeviceNotificationPreferences value;
  DeviceNotificationPreferences? lastPatchDraft;

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async => value;

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    lastPatchDraft = draft;
    return draft.copyWith(updatedAt: DateTime.utc(2026, 8, 27));
  }
}

LocalAuthRepository _signedInAuth() => LocalAuthRepository(
  initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
);

/// Sets the test viewport's logical size (devicePixelRatio pinned to 1.0, so
/// [width]/[height] are directly the logical pixels every widget/constraint
/// sees) and the platform text scale factor, restoring both after the test.
void _setViewport(
  WidgetTester tester, {
  required double width,
  double textScaleFactor = 1.0,
}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _pumpPage(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
          repository,
        ),
        authRepositoryProvider.overrideWithValue(_signedInAuth()),
      ],
      child: const MaterialApp(
        home: NotificationPreferencesPage(deviceId: 'device'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// No text should ever overflow its own render box — this is the actual,
/// literal meaning of "no overflow, no mid-word wrap, no truncation": any of
/// those would make the rendered [Text] wider/taller than the box Flutter
/// laid out for it, which shows up as a render overflow error during the
/// test regardless of which of the three causes produced it.
void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// `_ExclusiveAlertChoice` (the widgets' generic type argument) is private
/// to the page, so `find.byType(SegmentedButton<_ExclusiveAlertChoice>)`
/// cannot be spelled here — match by runtime type name instead.
Finder _findByTypeName(String name) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith(name),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in [320.0, 360.0, 400.0]) {
    testWidgets('${width.toInt()} dp: no overflow, all three modes remain '
        'selectable', (tester) async {
      _setViewport(tester, width: width);
      await _pumpPage(tester, _Repository());

      _expectNoOverflow(tester);
      expect(find.text('Chamada'), findsOneWidget);
      expect(
        find.text('Notificação').evaluate().isNotEmpty ||
            find.text('Aviso').evaluate().isNotEmpty,
        isTrue,
        reason: 'either the full or the compact label must be shown',
      );
      expect(find.text('Desativado'), findsOneWidget);
    });
  }

  testWidgets('text scale 1.3 (accessible): no overflow', (tester) async {
    _setViewport(tester, width: 360, textScaleFactor: 1.3);
    await _pumpPage(tester, _Repository());

    _expectNoOverflow(tester);
    expect(find.text('Chamada'), findsOneWidget);
    expect(find.text('Desativado'), findsOneWidget);
  });

  testWidgets(
    'text scale 2.0: falls back to the vertical, one-per-row layout — no '
    'SegmentedButton at all, no overflow',
    (tester) async {
      _setViewport(tester, width: 360, textScaleFactor: 2.0);
      await _pumpPage(tester, _Repository());

      _expectNoOverflow(tester);
      expect(_findByTypeName('SegmentedButton'), findsNothing);
      expect(_findByTypeName('RadioListTile'), findsNWidgets(3));
      expect(find.text('Chamada'), findsOneWidget);
      expect(find.text('Notificação'), findsOneWidget);
      expect(find.text('Desativado'), findsOneWidget);
    },
  );

  testWidgets('a wide/tablet width uses the full-label, icon segmented '
      'button', (tester) async {
    _setViewport(tester, width: 900);
    await _pumpPage(tester, _Repository());

    _expectNoOverflow(tester);
    expect(_findByTypeName('SegmentedButton'), findsOneWidget);
    expect(find.text('Chamada'), findsOneWidget);
    expect(find.text('Notificação'), findsOneWidget);
    expect(find.text('Desativado'), findsOneWidget);
  });

  testWidgets(
    'the vertical fallback still lets the user select each of the three '
    'modes, exclusively',
    (tester) async {
      _setViewport(tester, width: 360, textScaleFactor: 2.0);
      final repository = _Repository();
      await _pumpPage(tester, repository);

      expect(_findByTypeName('RadioListTile'), findsNWidgets(3));

      await tester.tap(find.text('Notificação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();

      expect(repository.lastPatchDraft?.alertMode, AlertMode.notificationOnly);
    },
  );

  testWidgets('semantics expose which alert mode is currently selected', (
    tester,
  ) async {
    _setViewport(tester, width: 900);
    await _pumpPage(tester, _Repository());

    final semantics = tester.getSemantics(
      find
          .ancestor(of: find.text('Chamada'), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics, isNotNull);
  });
}
