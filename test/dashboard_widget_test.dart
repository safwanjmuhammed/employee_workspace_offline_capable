import 'dart:async';

import 'package:employee_workspace_offline_capable/src/app.dart';
import 'package:employee_workspace_offline_capable/src/core/clock/company_clock.dart';
import 'package:employee_workspace_offline_capable/src/feature/data/repositories/workspace_repository.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/models/attendance.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/models/employee.dart';
import 'package:employee_workspace_offline_capable/src/feature/presentation/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoadingController extends WorkspaceController {
  @override
  Future<WorkspaceSnapshot> build() => Completer<WorkspaceSnapshot>().future;
}

class _PendingSyncController extends WorkspaceController {
  @override
  Future<WorkspaceSnapshot> build() async {
    return WorkspaceSnapshot(
      employee: const Employee(
        id: 'EMP-1024',
        name: 'Aarav Menon',
        department: 'Engineering',
        designation: 'Software Engineer',
        companyName: 'Test Organization',
        companyTimezone: 'Asia/Kolkata',
        office: OfficeConfig(
          name: 'Test Office',
          latitude: 10.0101,
          longitude: 76.3637,
          radiusMeters: 200,
        ),
      ),
      mergedRecords: [
        AttendanceRecord(
          date: '2026-11-19',
          checkInAtUtc: DateTime.utc(2026, 11, 19, 4, 0),
          checkInSyncStatus: SyncStatus.pending,
        ),
      ],
      outboxEvents: [
        AttendanceEvent(
          seq: 1,
          eventId: 'ev-1',
          type: AttendanceEventType.checkIn,
          workDate: '2026-11-19',
          occurredAtUtc: DateTime.utc(2026, 11, 19, 4, 0),
          latitude: 10.0101,
          longitude: 76.3637,
          accuracyMeters: 10,
          syncStatus: SyncStatus.pending,
          createdAtUtc: DateTime.utc(2026, 11, 19, 4, 0),
        ),
      ],
      lastUpdatedUtc: DateTime.utc(2026, 11, 19, 4, 0),
      isOffline: true,
    );
  }
}

void main() {
  testWidgets('Dashboard renders loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companyClockProvider.overrideWithValue(
            SystemCompanyClock(
              timezoneName: 'Asia/Kolkata',
              nowProvider: () => DateTime.utc(2026, 11, 19, 5, 0),
            ),
          ),
          workspaceControllerProvider.overrideWith(_LoadingController.new),
        ],
        child: const EmployeeWorkspaceApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading employee workspace...'), findsOneWidget);
  });

  testWidgets('Dashboard renders offline and Pending Sync indicators',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companyClockProvider.overrideWithValue(
            SystemCompanyClock(
              timezoneName: 'Asia/Kolkata',
              nowProvider: () => DateTime.utc(2026, 11, 19, 5, 0),
            ),
          ),
          workspaceControllerProvider.overrideWith(_PendingSyncController.new),
        ],
        child: const EmployeeWorkspaceApp(),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Aarav Menon'), findsOneWidget);
    expect(find.textContaining('1 pending sync'), findsOneWidget);
    expect(find.text('Pending Sync'), findsWidgets);
    expect(find.text('Sync Now'), findsOneWidget);
  });
}
