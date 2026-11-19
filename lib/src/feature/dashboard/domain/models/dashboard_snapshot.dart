import '../../../attendance/domain/models/attendance.dart';
import 'employee.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.employee,
    required this.mergedRecords,
    required this.outboxEvents,
    required this.lastUpdatedUtc,
    required this.isOffline,
    this.remoteError,
  });

  final Employee employee;
  final List<AttendanceRecord> mergedRecords;
  final List<AttendanceEvent> outboxEvents;
  final DateTime? lastUpdatedUtc;
  final bool isOffline;
  final String? remoteError;

  int get pendingCount =>
      outboxEvents.where((e) => e.syncStatus == SyncStatus.pending).length;

  int get rejectedCount =>
      outboxEvents.where((e) => e.syncStatus == SyncStatus.rejected).length;

  AttendanceRecord? todayRecord(String todayWorkDate) {
    for (final r in mergedRecords) {
      if (r.date == todayWorkDate) return r;
    }
    return null;
  }

  List<AttendanceRecord> get latestFiveRecords =>
      mergedRecords.take(5).toList();
}
