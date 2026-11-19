import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attendance/attendance_history_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'dev/dev_panel_sheet.dart';
import 'providers/app_providers.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  void _openDevPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DevPanelSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        ref.watch(workspaceControllerProvider).value?.pendingCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Workspace'),
        actions: [
          IconButton(
            tooltip: 'Simulation & Testing Controls',
            onPressed: _openDevPanel,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            DashboardScreen(
              onOpenHistory: () => setState(() => _tabIndex = 1),
            ),
            const AttendanceHistoryScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.history),
            ),
            label: 'Attendance',
          ),
        ],
      ),
    );
  }
}
