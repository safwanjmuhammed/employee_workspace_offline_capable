import '../../../../core/sync/sync_engine.dart';

enum AttendanceEventType {
  checkIn('check_in', 'Check In'),
  checkOut('check_out', 'Check Out');

  const AttendanceEventType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static AttendanceEventType fromWire(String value) {
    return AttendanceEventType.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => throw ArgumentError('Unknown event type: $value'),
    );
  }
}

enum SyncStatus {
  pending('pending', 'Pending Sync'),
  synced('synced', 'Synced'),
  rejected('rejected', 'Rejected');

  const SyncStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static SyncStatus fromWire(String value) {
    return SyncStatus.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => SyncStatus.pending,
    );
  }
}

enum TodayAttendanceStatus {
  notCheckedIn('Not Checked In'),
  checkedIn('Checked In'),
  checkedOut('Checked Out');

  const TodayAttendanceStatus(this.label);
  final String label;
}

/// Persisted outbox item representing a single user check-in or check-out tap.
class AttendanceEvent implements SyncableEvent {
  const AttendanceEvent({
    this.seq,
    required this.eventId,
    required this.type,
    required this.workDate,
    required this.occurredAtUtc,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.syncStatus,
    this.rejectReason,
    this.attempts = 0,
    this.lastError,
    required this.createdAtUtc,
  });

  final int? seq;
  @override
  final String eventId;
  final AttendanceEventType type;
  final String workDate;
  final DateTime occurredAtUtc;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final SyncStatus syncStatus;
  final String? rejectReason;
  final int attempts;
  final String? lastError;
  final DateTime createdAtUtc;

  Map<String, dynamic> toDbMap() => {
    if (seq != null) 'seq': seq,
    'event_id': eventId,
    'type': type.wireValue,
    'work_date': workDate,
    'occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_meters': accuracyMeters,
    'sync_status': syncStatus.wireValue,
    'reject_reason': rejectReason,
    'attempts': attempts,
    'last_error': lastError,
    'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
  };

  factory AttendanceEvent.fromDbMap(Map<String, dynamic> map) {
    return AttendanceEvent(
      seq: map['seq'] as int?,
      eventId: map['event_id'] as String,
      type: AttendanceEventType.fromWire(map['type'] as String),
      workDate: map['work_date'] as String,
      occurredAtUtc: DateTime.parse(map['occurred_at_utc'] as String).toUtc(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num).toDouble(),
      syncStatus: SyncStatus.fromWire(map['sync_status'] as String),
      rejectReason: map['reject_reason'] as String?,
      attempts: map['attempts'] as int? ?? 0,
      lastError: map['last_error'] as String?,
      createdAtUtc: DateTime.parse(map['created_at_utc'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toApiJson() => {
    'eventId': eventId,
    'type': type.wireValue,
    'workDate': workDate,
    'occurredAt': occurredAtUtc.toUtc().toIso8601String(),
    'location': {
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
    },
  };
}

/// Merged attendance day record combining server history and local outbox events.
class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    this.checkInAtUtc,
    this.checkOutAtUtc,
    this.checkInSyncStatus,
    this.checkOutSyncStatus,
    this.rejectReason,
  });

  final String date;
  final DateTime? checkInAtUtc;
  final DateTime? checkOutAtUtc;
  final SyncStatus? checkInSyncStatus;
  final SyncStatus? checkOutSyncStatus;
  final String? rejectReason;

  Duration? elapsedDuration(DateTime nowUtc) {
    if (checkInAtUtc == null) return null;
    final end = checkOutAtUtc ?? nowUtc;
    final diff = end.difference(checkInAtUtc!);
    return diff.isNegative ? Duration.zero : diff;
  }

  TodayAttendanceStatus get todayStatus {
    if (checkInAtUtc == null) return TodayAttendanceStatus.notCheckedIn;
    if (checkOutAtUtc == null) return TodayAttendanceStatus.checkedIn;
    return TodayAttendanceStatus.checkedOut;
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      date: json['date'] as String,
      checkInAtUtc: json['checkInAt'] != null
          ? DateTime.parse(json['checkInAt'] as String).toUtc()
          : null,
      checkOutAtUtc: json['checkOutAt'] != null
          ? DateTime.parse(json['checkOutAt'] as String).toUtc()
          : null,
      checkInSyncStatus: json['checkInAt'] != null ? SyncStatus.synced : null,
      checkOutSyncStatus: json['checkOutAt'] != null ? SyncStatus.synced : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'checkInAt': checkInAtUtc?.toUtc().toIso8601String(),
    'checkOutAt': checkOutAtUtc?.toUtc().toIso8601String(),
  };
}
