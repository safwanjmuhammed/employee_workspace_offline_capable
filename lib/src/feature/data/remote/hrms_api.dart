import 'package:dio/dio.dart';

import '../../../core/dio_api_service/interface/api_service_interface.dart';
import '../../domain/models/attendance.dart';
import '../../domain/models/employee.dart';

class AttendanceSubmissionResult {
  const AttendanceSubmissionResult({
    required this.replayed,
    required this.serverEventId,
  });

  final bool replayed;
  final String serverEventId;
}

class HrmsApi {
  HrmsApi(this._api);

  final IApiService _api;

  Future<Employee> fetchEmployee() async {
    final response = await _api.get('/employee/me');
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<AttendanceRecord>> fetchAttendance(String month) async {
    final response = await _api.get(
      '/attendance',
      queryParameters: {'month': month},
    );
    final map = response.data as Map<String, dynamic>;
    final list = map['records'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AttendanceSubmissionResult> submitAttendanceEvent(
    AttendanceEvent event,
  ) async {
    final response = await _api.post(
      '/attendance/events',
      data: event.toApiJson(),
      options: Options(
        headers: {'Idempotency-Key': event.eventId},
      ),
    );
    final body = response.data as Map<String, dynamic>? ?? const {};
    return AttendanceSubmissionResult(
      replayed: body['replayed'] == true,
      serverEventId: body['serverEventId']?.toString() ?? event.eventId,
    );
  }
}
