import 'package:employee_workspace_offline_capable/src/feature/domain/models/attendance.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/rules/attendance_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceRules', () {
    test('rejects check-out without prior check-in', () {
      final result = AttendanceRules.validateAction(
        type: AttendanceEventType.checkOut,
        currentStatus: TodayAttendanceStatus.notCheckedIn,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('after check-in'));
    });

    test('rejects second check-in on the same day', () {
      final result = AttendanceRules.validateAction(
        type: AttendanceEventType.checkIn,
        currentStatus: TodayAttendanceStatus.checkedIn,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('already checked in'));
    });

    test('permits check-out only when checked in', () {
      final result = AttendanceRules.validateAction(
        type: AttendanceEventType.checkOut,
        currentStatus: TodayAttendanceStatus.checkedIn,
      );

      expect(result.isValid, isTrue);
    });

    test('rejects attendance outside 200 m geofence', () {
      final outside = AttendanceRules.validateGeofence(
        distanceMeters: 245,
        radiusMeters: 200,
      );
      final inside = AttendanceRules.validateGeofence(
        distanceMeters: 180,
        radiusMeters: 200,
      );

      expect(outside.isValid, isFalse);
      expect(inside.isValid, isTrue);
    });
  });
}
