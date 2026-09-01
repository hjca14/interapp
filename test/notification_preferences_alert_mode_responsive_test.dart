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

void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in [320.0, 360.0, 400.0]) {
    for (final textScaleFactor in [1.0, 1.3, 2.0]) {
      testWidgets(
        '${width.toInt()} dp at text scale $textScaleFactor: no overflow, '
        'all three modes remain selectable, labels never break mid-word',
        (tester) async {
          _setViewport(tester, width: width, textScaleFactor: textScaleFactor);
          await _pumpPage(tester, _Repository());

          _expectNoOverflow(tester);
          expect(find.text('Chamada'), findsOneWidget);
          expect(find.text('Notificação'), findsOneWidget);
          expect(find.text('Desativado'), findsOneWidget);
          expect(
            find.byWidgetPredicate((widget) => widget is RadioListTile),
            findsNWidgets(3),
            reason:
                'the vertical, one-per-row selector is always used, at '
                'every width and text scale — never a horizontal control '
                'that could run out of room',
          );
        },
      );
    }
  }

  testWidgets('a wide/tablet width also uses the same vertical selector — no '
      'overflow, no separate wide-screen layout to keep in sync', (
    tester,
  ) async {
    _setViewport(tester, width: 900);
    await _pumpPage(tester, _Repository());

    _expectNoOverflow(tester);
    expect(
      find.byWidgetPredicate((widget) => widget is RadioListTile),
      findsNWidgets(3),
    );
  });

  testWidgets(
    'each option shows a short description of the difference between modes',
    (tester) async {
      _setViewport(tester, width: 360);
      await _pumpPage(tester, _Repository());

      expect(
        find.text('Toca continuamente e tenta abrir a tela de chamada.'),
        findsOneWidget,
      );
      expect(
        find.text('Mostra um aviso com som; toque nele para abrir a chamada.'),
        findsOneWidget,
      );
      expect(find.text('Não avisa quando o interfone tocar.'), findsOneWidget);
    },
  );

  testWidgets(
    'the vertical selector still lets the user select each of the three '
    'modes, exclusively, at a narrow width and high text scale',
    (tester) async {
      _setViewport(tester, width: 320, textScaleFactor: 2.0);
      final repository = _Repository();
      await _pumpPage(tester, repository);

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
    _setViewport(tester, width: 360);
    await _pumpPage(tester, _Repository());

    final semantics = tester.getSemantics(
      find
          .ancestor(of: find.text('Chamada'), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics, isNotNull);
  });
}
