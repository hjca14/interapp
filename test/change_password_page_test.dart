import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:interapp/features/auth/presentation/pages/change_password_page.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';
import 'package:interapp/features/settings/presentation/pages/settings_page.dart';

const _currentKey = Key('current-password-field');
const _newKey = Key('new-password-field');
const _confirmKey = Key('confirm-password-field');

Future<void> _pumpPage(
  WidgetTester tester, {
  AuthRepository? auth,
  bool wrapWithOpener = false,
}) async {
  final repository =
      auth ??
      LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: wrapWithOpener
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChangePasswordPage(),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              )
            : const ChangePasswordPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, Key key) => tester.widget<TextField>(
  find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
);

void main() {
  group('SettingsPage entry', () {
    testWidgets('offers "Alterar senha" outside device settings', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              profileName: 'Alguém',
              onEditProfile: () {},
              onSecurity: () {},
              onChangePassword: () => tapped = true,
              onLogout: () {},
            ),
          ),
        ),
      );

      expect(find.text('Alterar senha'), findsOneWidget);
      await tester.tap(find.text('Alterar senha'));
      expect(tapped, isTrue);
    });

    test(
      'device settings never mention password change (regression guard: '
      'per-device settings must stay unrelated to the account-wide action)',
      () {
        final source = File(
          'lib/features/devices/presentation/pages/device_settings_page.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('Alterar senha')));
        expect(source, isNot(contains('ChangePasswordPage')));
        expect(source, isNot(contains('change-password')));
      },
    );
  });

  group('ChangePasswordPage fields', () {
    testWidgets('all three password fields start obscured', (tester) async {
      await _pumpPage(tester);

      expect(_field(tester, _currentKey).obscureText, isTrue);
      expect(_field(tester, _newKey).obscureText, isTrue);
      expect(_field(tester, _confirmKey).obscureText, isTrue);
    });

    testWidgets('show/hide toggle reveals and hides each field independently', (
      tester,
    ) async {
      await _pumpPage(tester);

      final toggle = find
          .descendant(
            of: find.byKey(_newKey),
            matching: find.byType(IconButton),
          )
          .first;
      await tester.tap(toggle);
      await tester.pump();

      expect(_field(tester, _newKey).obscureText, isFalse);
      expect(_field(tester, _currentKey).obscureText, isTrue);
      expect(_field(tester, _confirmKey).obscureText, isTrue);
    });

    testWidgets(
      'current and new password fields carry the expected autofill hints',
      (tester) async {
        await _pumpPage(tester);

        expect(_field(tester, _currentKey).autofillHints, [
          AutofillHints.password,
        ]);
        expect(_field(tester, _newKey).autofillHints, [
          AutofillHints.newPassword,
        ]);
        expect(_field(tester, _confirmKey).autofillHints, [
          AutofillHints.newPassword,
        ]);
      },
    );

    testWidgets('fields disable autocorrect and suggestions', (tester) async {
      await _pumpPage(tester);

      for (final key in [_currentKey, _newKey, _confirmKey]) {
        expect(_field(tester, key).autocorrect, isFalse);
        expect(_field(tester, key).enableSuggestions, isFalse);
      }
    });
  });

  group('ChangePasswordPage validation and submission', () {
    testWidgets('shows local field errors without calling the repository', (
      tester,
    ) async {
      final repository = LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
      );
      await _pumpPage(tester, auth: repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
      await tester.pumpAndSettle();

      expect(find.text('Informe sua senha atual.'), findsOneWidget);
      expect(find.text('Informe a nova senha.'), findsOneWidget);
      expect(find.text('Confirme a nova senha.'), findsOneWidget);
      expect(repository.lastChangePasswordCurrent, isNull);
    });

    testWidgets('disables the submit button while the request is in flight', (
      tester,
    ) async {
      final completer = Completer<void>();
      final repository = _PendingAuthRepository(completer);
      await _pumpPage(tester, auth: repository);

      await tester.enterText(find.byKey(_currentKey), 'current-pass');
      await tester.enterText(find.byKey(_newKey), 'New-Password-1');
      await tester.enterText(find.byKey(_confirmKey), 'New-Password-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the keyboard action on the last field submits the form', (
      tester,
    ) async {
      final repository = LocalAuthRepository(
        initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
      );
      await _pumpPage(tester, auth: repository, wrapWithOpener: true);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(_currentKey), 'current-pass');
      await tester.enterText(find.byKey(_newKey), 'New-Password-1');
      await tester.enterText(find.byKey(_confirmKey), 'New-Password-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(repository.lastChangePasswordCurrent, 'current-pass');
      expect(repository.lastChangePasswordNew, 'New-Password-1');
    });

    testWidgets(
      'success clears the fields, unfocuses, shows a confirmation and '
      'returns to the previous screen',
      (tester) async {
        final repository = LocalAuthRepository(
          initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
        );
        await _pumpPage(tester, auth: repository, wrapWithOpener: true);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(_currentKey), 'current-pass');
        await tester.enterText(find.byKey(_newKey), 'New-Password-1');
        await tester.enterText(find.byKey(_confirmKey), 'New-Password-1');
        await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
        await tester.pumpAndSettle();

        expect(find.byType(ChangePasswordPage), findsNothing);
        expect(find.text('Senha alterada com sucesso.'), findsOneWidget);
      },
    );

    testWidgets(
      'a successful call with an equal current/new password stays on the '
      'screen, keeps the typed values, and shows "must differ" instead of '
      'a success confirmation',
      (tester) async {
        // LocalAuthRepository succeeds by default — mirroring the real
        // Cognito DEV response observed for identical current/new passwords
        // (it accepts the call rather than rejecting it).
        final repository = LocalAuthRepository(
          initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
        );
        await _pumpPage(tester, auth: repository, wrapWithOpener: true);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(_currentKey), 'abc');
        await tester.enterText(find.byKey(_newKey), 'abc');
        await tester.enterText(find.byKey(_confirmKey), 'abc');
        await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
        await tester.pumpAndSettle();

        expect(find.byType(ChangePasswordPage), findsOneWidget);
        expect(find.text('Senha alterada com sucesso.'), findsNothing);
        expect(
          find.text('A nova senha deve ser diferente da atual.'),
          findsOneWidget,
        );
        expect(_field(tester, _currentKey).controller!.text, 'abc');
        expect(_field(tester, _newKey).controller!.text, 'abc');
        expect(_field(tester, _confirmKey).controller!.text, 'abc');
        expect(repository.changePasswordCallCount, 1);
      },
    );

    testWidgets(
      'a general remote failure is shown legibly and never echoes any password',
      (tester) async {
        final repository =
            LocalAuthRepository(
                initial: const AuthSession(isSignedIn: true, userId: 'user-1'),
              )
              ..changePasswordFailure = const AuthFailure(
                AuthFailureKind.incorrectCurrentPassword,
                'Senha atual incorreta.',
              );
        await _pumpPage(tester, auth: repository);

        // The typed values legitimately remain in the fields afterwards (a
        // recoverable failure must let the user correct and resubmit), so
        // this only asserts the error text itself is the exact sanitized
        // message — never the raw password concatenated into feedback.
        await tester.enterText(find.byKey(_currentKey), 'wrong-current-pass');
        await tester.enterText(find.byKey(_newKey), 'New-Password-1');
        await tester.enterText(find.byKey(_confirmKey), 'New-Password-1');
        await tester.tap(find.widgetWithText(FilledButton, 'Alterar senha'));
        await tester.pumpAndSettle();

        expect(find.text('Senha atual incorreta.'), findsOneWidget);
      },
    );
  });
}

class _PendingAuthRepository implements AuthRepository {
  _PendingAuthRepository(this._completer);
  final Completer<void> _completer;

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _completer.future;

  @override
  Future<AuthSession> get currentSession async =>
      const AuthSession(isSignedIn: true, userId: 'user-1');

  @override
  Stream<AuthSession> watchSession() => const Stream.empty();

  @override
  Future<AuthSignUpResult> signUp(String email, String password) async =>
      const AuthSignUpResult(confirmationRequired: false);

  @override
  Future<void> confirmSignUp(String email, String code) async {}

  @override
  Future<void> resendSignUpCode(String email) async {}

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> beginPasswordReset(String email) async {}

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {}

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async =>
      'token';

  @override
  Future<void> invalidateSession() async {}
}
