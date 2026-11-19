import '../../../../core/location/geo.dart';
import '../models/attendance.dart';

class RuleResult {
  const RuleResult.ok()
      : isValid = true,
        errorMessage = null;

  const RuleResult.fail(this.errorMessage) : isValid = false;

  final bool isValid;
  final String? errorMessage;
}

/// Pure, side-effect-free attendance business rules.
abstract final class AttendanceRules {
  static RuleResult validateAction({
    required AttendanceEventType type,
    required TodayAttendanceStatus currentStatus,
  }) {
    switch (type) {
      case AttendanceEventType.checkIn:
        if (currentStatus == TodayAttendanceStatus.checkedIn) {
          return const RuleResult.fail('You have already checked in today.');
        }
        if (currentStatus == TodayAttendanceStatus.checkedOut) {
          return const RuleResult.fail(
            'Attendance is already completed for today.',
          );
        }
        return const RuleResult.ok();

      case AttendanceEventType.checkOut:
        if (currentStatus == TodayAttendanceStatus.notCheckedIn) {
          return const RuleResult.fail(
            'Check-out is only permitted after check-in.',
          );
        }
        if (currentStatus == TodayAttendanceStatus.checkedOut) {
          return const RuleResult.fail('You have already checked out today.');
        }
        return const RuleResult.ok();
    }
  }

  static RuleResult validateGeofence({
    required double distanceMeters,
    required double radiusMeters,
  }) {
    if (distanceMeters <= radiusMeters) {
      return const RuleResult.ok();
    }
    final distLabel = Geo.formatDistance(distanceMeters);
    return RuleResult.fail(
      'You are $distLabel from the office. '
      'Attendance is permitted only within ${radiusMeters.round()} m.',
    );
  }

  /// Merges server-provided attendance records with local outbox events so
  /// pending and recently synced local actions appear immediately in today's
  /// summary and history.
  static List<AttendanceRecord> mergeHistoryWithOutbox({
    required List<AttendanceRecord> serverRecords,
    required List<AttendanceEvent> outboxEvents,
  }) {
    final byDate = <String, AttendanceRecord>{
      for (final rec in serverRecords) rec.date: rec,
    };

    // Process outbox in chronological sequence order.
    final ordered = [...outboxEvents]
      ..sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));

    for (final ev in ordered) {
      if (ev.syncStatus == SyncStatus.rejected) {
        continue;
      }
      final existing = byDate[ev.workDate];
      if (ev.type == AttendanceEventType.checkIn) {
        byDate[ev.workDate] = AttendanceRecord(
          date: ev.workDate,
          checkInAtUtc: ev.occurredAtUtc,
          checkOutAtUtc: existing?.checkOutAtUtc,
          checkInSyncStatus: ev.syncStatus,
          checkOutSyncStatus: existing?.checkOutSyncStatus,
        );
      } else {
        byDate[ev.workDate] = AttendanceRecord(
          date: ev.workDate,
          checkInAtUtc: existing?.checkInAtUtc,
          checkOutAtUtc: ev.occurredAtUtc,
          checkInSyncStatus: existing?.checkInSyncStatus,
          checkOutSyncStatus: ev.syncStatus,
        );
      }
    }

    final merged = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }
}
