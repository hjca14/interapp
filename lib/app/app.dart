import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/core/router/app_router.dart';

class InterApp extends ConsumerWidget {
  const InterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'InterBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1246A8), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF3F7FF),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1246A8), foregroundColor: Colors.white),
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFFE8F0FF), indicatorColor: Color(0xFFB8D1FF)),
      ),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
