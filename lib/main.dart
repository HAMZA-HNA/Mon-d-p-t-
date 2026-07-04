import 'package:flutter/material.dart';

import 'router_web_screen.dart';

void main() {
  runApp(const OrangeWifiApp());
}

class OrangeWifiApp extends StatelessWidget {
  const OrangeWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mon WiFi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7900)),
      ),
      home: const RouterWebScreen(),
    );
  }
}
