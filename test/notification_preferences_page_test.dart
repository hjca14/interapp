import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/network/api_failure.dart';
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
  Object? getError;
  Object? patchError;
  Completer<DeviceNotificationPreferences>? pendingGet;
  Completer<DeviceNotificationPreferences>? pendingPatch;
  int getCalls = 0;
  int patchCalls = 0;
  DeviceNotificationPreferences? lastPatchDraft;

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async {
    getCalls++;
    if (getError case final Object error) throw error;
    return pendingGet?.future ?? value;
  }

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    patchCalls++;
    lastPatchDraft = draft;
    if (patchError case final Object error) throw error;
    return pendingPatch?.future ??
        draft.copyWith(updatedAt: DateTime.utc(2026, 8, 27));
  }
}

// A fresh `LocalAuthRepository` per call so no test can ever leak
// session-mutating state (e.g. sign-out) into another test.
LocalAuthRepository _signedInAuth() => LocalAuthRepository(
  initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
);

Future<void> _pumpPage(
  WidgetTester tester,
  _Repository repository, {
  bool wrapWithOpener = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
          repository,
        ),
        authRepositoryProvider.overrideWithValue(_signedInAuth()),
      ],
      child: MaterialApp(
        home: wrapWithOpener
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NotificationPreferencesPage(
                            deviceId: 'device',
                            deviceName: 'Portaria',
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              )
            : const NotificationPreferencesPage(
                deviceId: 'device',
                deviceName: 'Portaria',
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('loading, then ready with no Salvar button anywhere', (
    tester,
  ) async {
    final repository = _Repository()
      ..pendingGet = Completer<DeviceNotificationPreferences>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
            repository,
          ),
          authRepositoryProvider.overrideWithValue(_signedInAuth()),
        ],
        child: const MaterialApp(
          home: NotificationPreferencesPage(
            deviceId: 'device',
            deviceName: 'Portaria',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.pendingGet!.complete(DeviceNotificationPreferences());
    await tester.pumpAndSettle();

    expect(find.text('Receber ligação'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar'), findsNothing);
    expect(find.text('Salvar'), findsNothing);
  });

  testWidgets('a load error offers retry', (tester) async {
    final repository = _Repository()
      ..getError = const ApiFailure(ApiFailureKind.offline, 'Sem conexão.');
    await _pumpPage(tester, repository);

    expect(find.text('Sem conexão.'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Tentar novamente'),
      findsOneWidget,
    );

    repository.getError = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Receber ligação'), findsOneWidget);
  });

  testWidgets(
    'autosave is silent on success: no "Salvando...", no "Salvo"/"Tudo '
    'salvo", no SnackBar, before, during, or after a write',
    (tester) async {
      final repository = _Repository();
      await _pumpPage(tester, repository);

      expect(find.text('Salvando...'), findsNothing);
      expect(find.textContaining('Salvo'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Receber ligação'));
      await tester.pump();
      expect(find.text('Salvando...'), findsNothing);
      expect(find.textContaining('Salvo'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(repository.patchCalls, 0, reason: 'debounce has not fired yet');

      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();

      expect(repository.patchCalls, 1);
      expect(find.text('Salvando...'), findsNothing);
      expect(find.textContaining('Salvo'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'controls remain editable and tappable while autosave is in flight',
    (tester) async {
      final pending = Completer<DeviceNotificationPreferences>();
      final repository = _Repository()..pendingPatch = pending;
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Receber ligação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pump();

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Receber notificação'),
      );
      expect(
        switchTile.onChanged,
        isNotNull,
        reason: 'autosave must never disable the controls',
      );

      await tester.tap(find.text('Receber notificação'));
      await tester.pump();

      // Clear pendingPatch before completing so the follow-up flush the
      // controller schedules for this second edit (draft changed again
      // while the first PATCH was in flight) echoes back what was actually
      // sent, instead of resolving to this same stale value forever.
      final firstPatch = repository.pendingPatch!;
      repository.pendingPatch = null;
      firstPatch.complete(
        DeviceNotificationPreferences(alertMode: AlertMode.ringOnly),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(repository.patchCalls, 2);
    },
  );

  testWidgets(
    'a save failure shows a sanitized message with a "Tentar novamente" '
    'action, and never claims success',
    (tester) async {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Receber ligação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, 'Tentar novamente'),
        findsOneWidget,
      );
      expect(find.textContaining('Salvo'), findsNothing);

      repository.patchError = null;
      await tester.tap(find.widgetWithText(SnackBarAction, 'Tentar novamente'));
      await tester.pumpAndSettle();

      expect(repository.patchCalls, 2);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Salvo'), findsNothing);
    },
  );

  testWidgets(
    'retry resends the current draft, not a stale snapshot of what failed',
    (tester) async {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Receber ligação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();

      expect(repository.patchCalls, 1);
      expect(repository.lastPatchDraft?.alertMode.includesRing, isFalse);
      expect(repository.lastPatchDraft?.alertMode.includesNotification, isTrue);

      repository.patchError = null;
      await tester.tap(find.widgetWithText(SnackBarAction, 'Tentar novamente'));
      await tester.pumpAndSettle();

      expect(repository.patchCalls, 2);
      // The resent payload is still the latest desired draft (ring off,
      // notification untouched) — not some earlier/default value.
      expect(repository.lastPatchDraft?.alertMode.includesRing, isFalse);
      expect(repository.lastPatchDraft?.alertMode.includesNotification, isTrue);
    },
  );

  testWidgets(
    'repeated failures from the same retry never stack multiple SnackBars',
    (tester) async {
      final repository = _Repository()
        ..patchError = const ApiFailure(ApiFailureKind.offline, 'Offline');
      await _pumpPage(tester, repository);

      await tester.tap(find.text('Receber ligação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Retry again while still failing — must replace, not stack.
      await tester.tap(find.widgetWithText(SnackBarAction, 'Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(repository.patchCalls, 2);
    },
  );

  testWidgets('leaving the page never shows a discard-changes dialog', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpPage(tester, repository, wrapWithOpener: true);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receber ligação'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
    'disabling the schedule saves enabled:false and preserves the previous '
    'days/times/timezone, which reappear once reactivated',
    (tester) async {
      final schedule = QuietSchedule(
        enabled: true,
        timezone: 'America/Recife',
        days: const {2, 4},
        startTime: ClockTime(hour: 23, minute: 0),
        endTime: ClockTime(hour: 6, minute: 0),
        behavior: QuietScheduleBehavior.blockAll,
      );
      final repository = _Repository(
        value: DeviceNotificationPreferences(quietSchedule: schedule),
      );
      await _pumpPage(tester, repository);

      expect(find.text('23:00'), findsOneWidget);

      await tester.tap(find.text('Ativar horários sem ligação'));
      await tester.pump(
        DeviceNotificationPreferencesController.debounceDuration,
      );
      await tester.pumpAndSettle();

      expect(repository.patchCalls, 1);
      expect(
        find.text('23:00'),
        findsNothing,
        reason: 'collapsed while disabled',
      );

      await tester.tap(find.text('Ativar horários sem ligação'));
      await tester.pumpAndSettle();

      expect(
        find.text('23:00'),
        findsOneWidget,
        reason: 'previous time/day/timezone values are preserved, not cleared',
      );
      expect(find.text('America/Recife'), findsOneWidget);
    },
  );

  testWidgets('an unavailable timezone is reported without crashing', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceNotificationPreferencesRepositoryProvider.overrideWithValue(
            repository,
          ),
          timezoneLoaderProvider.overrideWithValue(
            () async => throw const TimezoneUnavailableException(),
          ),
          authRepositoryProvider.overrideWithValue(_signedInAuth()),
        ],
        child: const MaterialApp(
          home: NotificationPreferencesPage(
            deviceId: 'device',
            deviceName: 'Portaria',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ativar horários sem ligação'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fuso horário'), findsOneWidget);
    expect(find.text('Receber ligação'), findsOneWidget);
  });

  testWidgets(
    'no obsolete wording (local network, its own "silent" option) ever '
    'appears',
    (tester) async {
      final repository = _Repository(
        value: DeviceNotificationPreferences(
          quietSchedule: QuietSchedule(
            enabled: true,
            timezone: 'America/Recife',
            days: const {1},
            startTime: ClockTime(hour: 22, minute: 0),
            endTime: ClockTime(hour: 7, minute: 0),
          ),
        ),
      );
      await _pumpPage(tester, repository);

      expect(find.text('Horários sem ligação'), findsOneWidget);
      expect(find.text('Só notificação'), findsOneWidget);
      expect(find.text('Bloquear tudo'), findsOneWidget);
      expect(find.text('Presença'), findsNothing);
      expect(find.text('Notificação sem som'), findsNothing);
      expect(find.textContaining('rede local'), findsNothing);
      expect(find.textContaining('Não Perturbe'), findsNothing);
    },
  );
}
