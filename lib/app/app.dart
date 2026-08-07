import 'package:flutter/material.dart';
import 'package:interapp/features/home/presentation/pages/home_page.dart';

class InterApp extends StatelessWidget {
  const InterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InterApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF111BA7),
        ),
      ),
      home: const HomePage(),
    );
  }
}