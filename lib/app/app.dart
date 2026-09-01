import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/router/app_router.dart';
import 'package:interapp/features/devices/presentation/widgets/ring_call_overlay.dart';

/// Root widget of the app.
///
/// Sets up the Material theme (InterBridge blue) and wires [MaterialApp.router]
/// to the [appRouterProvider], so all navigation goes through GoRouter instead
/// of a manually managed [Navigator]. [RingCallOverlay] is stacked on top via
/// `builder` — deliberately outside GoRouter's own routing — so an incoming
/// call is presented without ever changing the current route; see its doc
/// comment for why.
class InterApp extends ConsumerWidget {
  const InterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'InterBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Seed color drives Material 3's generated color scheme; the other
        // colors below pin the specific blue tones from the brand palette.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1246A8),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F7FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1246A8),
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFE8F0FF),
          indicatorColor: Color(0xFFB8D1FF),
        ),
      ),
      // `ref.watch` (not `ref.read`) so the router rebuilds if the provider
      // itself is ever swapped, e.g. in tests.
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) =>
          Stack(children: [?child, const RingCallOverlay()]),
    );
  }
}
