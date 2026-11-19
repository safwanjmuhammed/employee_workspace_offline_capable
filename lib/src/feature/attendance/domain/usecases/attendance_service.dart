import 'package:uuid/uuid.dart';

import '../../../../core/clock/company_clock.dart';
import '../../../../core/location/geo.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/sync/sync_engine.dart';
import '../models/attendance.dart';
import '../repositories/attendance_repository.dart';
import '../rules/attendance_rules.dart';

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

/// Application use case that orchestrates attendance validation, location
/// verification, local outbox persistence, and synchronization.
class AttendanceService {
  AttendanceService({
    required this.clock,
    required this.locationService,
    required this.repository,
    required this.syncEngine,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final CompanyClock clock;
  final LocationService locationService;
  final AttendanceRepository repository;
  final SyncEngine<AttendanceEvent> syncEngine;
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
      final office = await repository.getOfficeConfig();
      final today = clock.todayWorkDate();
      final currentStatus = await repository.getTodayStatus(today);

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

      final locResult = await locationService.getCurrentLocation(
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

          final nowUtc = clock.nowUtc();
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
            final saved = await repository.enqueueEvent(event);
            final summary = await syncEngine.syncPending();
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
