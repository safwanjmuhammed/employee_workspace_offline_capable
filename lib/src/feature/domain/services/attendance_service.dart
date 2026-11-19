import 'package:uuid/uuid.dart';

import '../../../config/app_config.dart';
import '../../../core/clock/company_clock.dart';
import '../../../core/location/geo.dart';
import '../../../core/location/location_service.dart';
import '../../data/local/cache_store.dart';
import '../../data/local/outbox_store.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../rules/attendance_rules.dart';
import 'sync_engine.dart';

enum AttendanceActionOutcome {
  success,
  ruleRejected,
  permissionDenied,
  permissionPermanentlyDenied,
  locationServiceDisabled,
  locationUnavailable,
  outsideGeofence,
  alreadyInFlight,
}

class AttendanceActionResult {
  const AttendanceActionResult({
    required this.outcome,
    this.message,
    this.event,
    this.syncSummary,
  });

  final AttendanceActionOutcome outcome;
  final String? message;
  final AttendanceEvent? event;
  final SyncSummary? syncSummary;

  bool get isSuccess => outcome == AttendanceActionOutcome.success;
}

class AttendanceService {
  AttendanceService({
    required CompanyClock clock,
    required LocationService locationService,
    required CacheStore cache,
    required OutboxStore outbox,
    required SyncEngine syncEngine,
    Uuid? uuid,
  })  : _clock = clock,
        _locationService = locationService,
        _cache = cache,
        _outbox = outbox,
        _syncEngine = syncEngine,
        _uuid = uuid ?? const Uuid();

  final CompanyClock _clock;
  final LocationService _locationService;
  final CacheStore _cache;
  final OutboxStore _outbox;
  final SyncEngine _syncEngine;
  final Uuid _uuid;

  bool _inFlight = false;

  Future<AttendanceActionResult> performAction(AttendanceEventType type) async {
    if (_inFlight) {
      return const AttendanceActionResult(
        outcome: AttendanceActionOutcome.alreadyInFlight,
        message: 'An attendance action is already in progress.',
      );
    }

    _inFlight = true;
    try {
      final cachedEmployee = await _cache.readEmployee();
      final office = cachedEmployee?.value.office ??
          const OfficeConfig(
            name: 'Office',
            latitude: AppConfig.defaultOfficeLat,
            longitude: AppConfig.defaultOfficeLng,
            radiusMeters: AppConfig.defaultOfficeRadiusMeters,
          );

      final cachedHistory = await _cache.readAttendanceHistory();
      final outboxEvents = await _outbox.getAllEvents();
      final merged = AttendanceRules.mergeHistoryWithOutbox(
        serverRecords: cachedHistory?.value ?? const [],
        outboxEvents: outboxEvents,
      );
      final today = _clock.todayWorkDate();
      final todayRecord = merged.where((r) => r.date == today).firstOrNull;
      final currentStatus =
          todayRecord?.todayStatus ?? TodayAttendanceStatus.notCheckedIn;

      final ruleCheck = AttendanceRules.validateAction(
        type: type,
        currentStatus: currentStatus,
      );
      if (!ruleCheck.isValid) {
        return AttendanceActionResult(
          outcome: AttendanceActionOutcome.ruleRejected,
          message: ruleCheck.errorMessage,
        );
      }

      final locResult = await _locationService.getCurrentLocation(
        officeLat: office.latitude,
        officeLng: office.longitude,
      );

      switch (locResult) {
        case LocationPermissionDenied():
          return const AttendanceActionResult(
            outcome: AttendanceActionOutcome.permissionDenied,
            message:
                'Location permission is required to verify you are at the office.',
          );
        case LocationPermissionPermanentlyDenied():
          return const AttendanceActionResult(
            outcome: AttendanceActionOutcome.permissionPermanentlyDenied,
            message:
                'Location permission is permanently denied. Please enable it in App Settings.',
          );
        case LocationServiceDisabled():
          return const AttendanceActionResult(
            outcome: AttendanceActionOutcome.locationServiceDisabled,
            message:
                'Location services are turned off. Please enable GPS to continue.',
          );
        case LocationUnavailable(:final reason):
          return AttendanceActionResult(
            outcome: AttendanceActionOutcome.locationUnavailable,
            message: reason ?? 'Unable to determine your current GPS location.',
          );
        case LocationSuccess(:final point):
          final distance = Geo.distanceMeters(
            lat1: point.latitude,
            lng1: point.longitude,
            lat2: office.latitude,
            lng2: office.longitude,
          );
          final geofenceCheck = AttendanceRules.validateGeofence(
            distanceMeters: distance,
            radiusMeters: office.radiusMeters,
          );
          if (!geofenceCheck.isValid) {
            return AttendanceActionResult(
              outcome: AttendanceActionOutcome.outsideGeofence,
              message: geofenceCheck.errorMessage,
            );
          }

          final nowUtc = _clock.nowUtc();
          final event = AttendanceEvent(
            eventId: _uuid.v4(),
            type: type,
            workDate: today,
            occurredAtUtc: nowUtc,
            latitude: point.latitude,
            longitude: point.longitude,
            accuracyMeters: point.accuracyMeters,
            syncStatus: SyncStatus.pending,
            createdAtUtc: nowUtc,
          );

          try {
            final saved = await _outbox.enqueue(event);
            final summary = await _syncEngine.syncPending();
            return AttendanceActionResult(
              outcome: AttendanceActionOutcome.success,
              event: saved,
              syncSummary: summary,
              message: summary.remainingPendingCount == 0
                  ? '${type.label} recorded and synced.'
                  : '${type.label} saved offline (Pending Sync).',
            );
          } on DuplicateLocalEventException catch (e) {
            return AttendanceActionResult(
              outcome: AttendanceActionOutcome.ruleRejected,
              message: e.message,
            );
          }
      }
    } finally {
      _inFlight = false;
    }
  }
}
