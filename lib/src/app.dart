import 'package:flutter/material.dart';

import 'feature/presentation/home_shell.dart';

class EmployeeWorkspaceApp extends StatelessWidget {
  const EmployeeWorkspaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Workspace',
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
