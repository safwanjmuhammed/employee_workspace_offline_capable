import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../../domain/models/attendance.dart';

class DuplicateLocalEventException implements Exception {
  const DuplicateLocalEventException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OutboxStore {
  OutboxStore(this._db);

  final AppDatabase _db;

  Future<AttendanceEvent> enqueue(AttendanceEvent event) async {
    try {
      final seq = await _db.db.insert(
        'attendance_outbox',
        event.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return AttendanceEvent(
        seq: seq,
        eventId: event.eventId,
        type: event.type,
        workDate: event.workDate,
        occurredAtUtc: event.occurredAtUtc,
        latitude: event.latitude,
        longitude: event.longitude,
        accuracyMeters: event.accuracyMeters,
        syncStatus: event.syncStatus,
        rejectReason: event.rejectReason,
        attempts: event.attempts,
        lastError: event.lastError,
        createdAtUtc: event.createdAtUtc,
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const DuplicateLocalEventException(
          'An attendance event for this action already exists today.',
        );
      }
      rethrow;
    }
  }

  Future<List<AttendanceEvent>> getPendingInOrder() async {
    final rows = await _db.db.query(
      'attendance_outbox',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.pending.wireValue],
      orderBy: 'seq ASC',
    );
    return rows.map(AttendanceEvent.fromDbMap).toList();
  }

  Future<List<AttendanceEvent>> getAllEvents() async {
    final rows = await _db.db.query(
      'attendance_outbox',
      orderBy: 'seq DESC',
    );
    return rows.map(AttendanceEvent.fromDbMap).toList();
  }

  Future<int> pendingCount() async {
    final result = await _db.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM attendance_outbox WHERE sync_status = ?',
      [SyncStatus.pending.wireValue],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markSynced(String eventId) async {
    await _db.db.update(
      'attendance_outbox',
      {
        'sync_status': SyncStatus.synced.wireValue,
        'last_error': null,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> markRejected(String eventId, String reason) async {
    await _db.db.update(
      'attendance_outbox',
      {
        'sync_status': SyncStatus.rejected.wireValue,
        'reject_reason': reason,
        'last_error': reason,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> recordAttemptFailure(String eventId, String error) async {
    await _db.db.rawUpdate(
      '''
      UPDATE attendance_outbox
      SET attempts = attempts + 1, last_error = ?
      WHERE event_id = ?
      ''',
      [error, eventId],
    );
  }
}
