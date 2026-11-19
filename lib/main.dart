import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/clock/company_clock.dart';
import 'src/core/db/app_database.dart';
import 'src/feature/dashboard/presentation/providers/workspace_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemCompanyClock.ensureTimezoneInitialized();

  final database = await AppDatabase.open();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: const EmployeeWorkspaceApp(),
    ),
  );
}
