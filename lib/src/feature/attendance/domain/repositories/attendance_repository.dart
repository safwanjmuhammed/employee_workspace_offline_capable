import '../../../dashboard/domain/models/employee.dart';
import '../models/attendance.dart';

class DuplicateLocalEventException implements Exception {
  const DuplicateLocalEventException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Domain repository contract for attendance persistence and status queries.
abstract interface class AttendanceRepository {
  Future<OfficeConfig> getOfficeConfig();
  Future<TodayAttendanceStatus> getTodayStatus(String workDate);
  Future<AttendanceEvent> enqueueEvent(AttendanceEvent event);
}
