import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/auth_pages.dart';
import '../../features/auth/presentation/pages/security_settings_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/domain/entities/auth_session.dart';
import '../../features/devices/presentation/pages/api_device_detail_page.dart';
import '../../features/home/presentation/pages/home_page.dart';

const _authenticationPaths = {
  '/login',
  '/sign-up',
  '/confirm',
  '/forgot-password',
  '/reset',
};

/// Application router driven by the provider-independent auth session.
final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (_, state) => _redirectForSession(session, state),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const _BootstrapPage(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/sign-up', builder: (_, _) => const SignUpPage()),
      GoRoute(
        path: '/confirm',
        builder: (_, state) => CodePage(email: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset',
        builder: (_, state) => CodePage(
          email: state.extra as String? ?? '',
          passwordReset: true,
        ),
      ),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/security',
        builder: (_, _) => const SecuritySettingsPage(),
      ),
      GoRoute(
        path: '/devices/:deviceId',
        name: 'device-detail',
        builder: (_, state) {
          return ApiDeviceDetailPage(
            deviceId: state.pathParameters['deviceId']!,
          );
        },
      ),
    ],
  );
});

String? _redirectForSession(
  AsyncValue<AuthSession> session,
  GoRouterState routerState,
) {
  final location = routerState.matchedLocation;
  if (session.isLoading) return location == '/splash' ? null : '/splash';

  final signedIn = session.value?.isSignedIn == true;
  final isAuthenticationPath = _authenticationPaths.contains(location);
  if (!signedIn && !isAuthenticationPath) return '/login';
  if (signedIn && (isAuthenticationPath || location == '/splash')) return '/';
  return null;
}

class _BootstrapPage extends StatelessWidget {
  const _BootstrapPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
