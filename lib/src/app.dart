import 'package:flutter/material.dart';

import 'feature/presentation/home_shell.dart';

class RebsWorkspaceApp extends StatelessWidget {
  const RebsWorkspaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REBS HRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1D4ED8),
        cardTheme: const CardThemeData(
          elevation: 0.5,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const HomeShell(),
    );
  }
}
