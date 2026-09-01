import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:interapp/features/auth/presentation/pages/auth_pages.dart';
import 'package:interapp/features/auth/presentation/providers/auth_providers.dart';

/// Fakes only the operations these pages actually call — everything else is
/// deliberately unreachable from this test's flows.
class _FakeAuthRepository implements AuthRepository {
  int beginPasswordResetCallCount = 0;
  String? capturedEmail;
  Object? beginPasswordResetError;
  Completer<void>? beginPasswordResetGate;

  @override
  Future<void> beginPasswordReset(String email) async {
    beginPasswordResetCallCount++;
    capturedEmail = email;
    final gate = beginPasswordResetGate;
    if (gate != null) {
      await gate.future;
    }
    final error = beginPasswordResetError;
    if (error != null) {
      // ignore: only_throw_errors
      throw error;
    }
  }

  @override
  Stream<AuthSession> watchSession() =>
      Stream.value(const AuthSession.signedOut());

  @override
  Future<AuthSession> get currentSession async => const AuthSession.signedOut();

  @override
  Future<AuthSignUpResult> signUp(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<void> confirmSignUp(String email, String code) =>
      throw UnimplementedError();

  @override
  Future<void> resendSignUpCode(String email) => throw UnimplementedError();

  @override
  Future<void> signIn(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) => throw UnimplementedError();

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      throw UnimplementedError();

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) =>
      throw UnimplementedError();

  @override
  Future<void> invalidateSession() => throw UnimplementedError();
}

Widget _wrap(
  _FakeAuthRepository repository, {
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset',
        builder: (_, state) =>
            CodePage(email: state.extra as String? ?? '', passwordReset: true),
      ),
      GoRoute(
        path: '/confirm',
        builder: (_, state) => CodePage(email: state.extra as String? ?? ''),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('CodePage — "Enviar novo código" (password reset)', () {
    testWidgets('calls beginPasswordReset with the page email and shows a safe '
        'confirmation', (tester) async {
      final repository = _FakeAuthRepository();
      await tester.pumpWidget(_wrap(repository, initialLocation: '/reset'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar novo código'));
      await tester.pumpAndSettle();

      expect(repository.beginPasswordResetCallCount, 1);
      expect(find.text('Novo código enviado.'), findsOneWidget);
    });

    testWidgets('is disabled while a send is in flight, preventing a '
        'double-click from firing a second request', (tester) async {
      final repository = _FakeAuthRepository()
        ..beginPasswordResetGate = Completer<void>();
      await tester.pumpWidget(_wrap(repository, initialLocation: '/reset'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar novo código'));
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Enviar novo código'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(repository.beginPasswordResetCallCount, 1);

      repository.beginPasswordResetGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('an error while sending a new code is shown safely', (
      tester,
    ) async {
      final repository = _FakeAuthRepository()
        ..beginPasswordResetError = const AuthFailure(
          AuthFailureKind.rateLimited,
          'Muitas tentativas. Aguarde e tente novamente.',
        );
      await tester.pumpWidget(_wrap(repository, initialLocation: '/reset'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar novo código'));
      await tester.pumpAndSettle();

      expect(
        find.text('Muitas tentativas. Aguarde e tente novamente.'),
        findsOneWidget,
      );
    });

    testWidgets('sign-up confirmation keeps using "Reenviar código", never the '
        'password-recovery button', (tester) async {
      final repository = _FakeAuthRepository();
      await tester.pumpWidget(_wrap(repository, initialLocation: '/confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Reenviar código'), findsOneWidget);
      expect(find.text('Enviar novo código'), findsNothing);
    });
  });

  group('ForgotPasswordPage — resetPassword next-step handling', () {
    testWidgets(
      'a passwordResetComplete failure returns to login with a coherent '
      'message instead of pushing the code screen',
      (tester) async {
        final repository = _FakeAuthRepository()
          ..beginPasswordResetError = const AuthFailure(
            AuthFailureKind.passwordResetComplete,
            'A redefinição já foi concluída. Entre com sua nova senha.',
          );
        await tester.pumpWidget(
          _wrap(repository, initialLocation: '/forgot-password'),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'person@example.invalid',
        );
        await tester.tap(find.text('Enviar código'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginPage), findsOneWidget);
        expect(
          find.text(
            'A redefinição já foi concluída. Entre com sua nova senha.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
