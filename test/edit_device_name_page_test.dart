import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/devices/data/repositories/fake_device_repository.dart';
import 'package:interapp/features/devices/domain/entities/api_device.dart';
import 'package:interapp/features/devices/presentation/pages/edit_device_name_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/sharing/domain/entities/device_access.dart';

void main() {
  const deviceId = 'ib-00000000000000000000000000000001';

  Widget subject({String? initialName}) {
    return ProviderScope(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(
          FakeDeviceRepository(
            devices: [
              ApiDeviceDetail(
                deviceId: deviceId,
                displayName: initialName,
                ownershipStatus: 'claimed',
                provisioningStatus: 'active',
                role: DeviceRole.owner,
              ),
            ],
          ),
        ),
      ],
      child: MaterialApp(
        home: EditDeviceNamePage(deviceId: deviceId, initialName: initialName),
      ),
    );
  }

  testWidgets('pre-fills the field with the current name', (tester) async {
    await tester.pumpWidget(subject(initialName: 'Portaria'));
    expect(find.text('Portaria'), findsOneWidget);
  });

  testWidgets('starts empty when there is no custom name', (tester) async {
    await tester.pumpWidget(subject());
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('Salvar is disabled while the field is blank', (tester) async {
    await tester.pumpWidget(subject());
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'Casa');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Usar nome padrão only shows when there is a custom name', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    expect(find.text('Usar nome padrão'), findsNothing);

    await tester.pumpWidget(subject(initialName: 'Portaria'));
    expect(find.text('Usar nome padrão'), findsOneWidget);
  });

  testWidgets('the name field enforces the backend character limit', (
    tester,
  ) async {
    await tester.pumpWidget(subject());
    await tester.enterText(
      find.byType(TextField),
      'a' * (kDeviceDisplayNameMaxLength + 20),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      kDeviceDisplayNameMaxLength,
    );
  });

  testWidgets('saving successfully pops the page', (tester) async {
    await tester.pumpWidget(subject(initialName: 'Portaria'));
    await tester.enterText(find.byType(TextField), 'Minha casa');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(EditDeviceNamePage), findsNothing);
  });

  testWidgets('double tap while saving only submits once', (tester) async {
    await tester.pumpWidget(subject(initialName: 'Portaria'));
    await tester.enterText(find.byType(TextField), 'Minha casa');
    final save = find.widgetWithText(FilledButton, 'Salvar');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Salvando...'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(EditDeviceNamePage), findsNothing);
  });
}
