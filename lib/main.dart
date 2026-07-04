import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'state/router_controller.dart';

void main() {
  runApp(const OrangeWifiApp());
}

class OrangeWifiApp extends StatelessWidget {
  const OrangeWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RouterController(),
      child: MaterialApp(
        title: 'WiFi Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF7900), // Orange
          ),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<RouterController>().status;
    if (status == SessionStatus.loggedIn) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}
