import '../../../../config/app_config.dart';
import '../../../dashboard/data/datasources/cache_store.dart';
import '../../../dashboard/domain/models/employee.dart';
import '../../domain/models/attendance.dart';
import '../../domain/repositories/attendance_repository.dart';
import '../../domain/rules/attendance_rules.dart';
import '../datasources/outbox_store.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  AttendanceRepositoryImpl({
    required this.cache,
    required this.outbox,
  });

  final CacheStore cache;
  final OutboxStore outbox;

  @override
  Future<OfficeConfig> getOfficeConfig() async {
    final cachedEmployee = await cache.readEmployee();
    return cachedEmployee?.value.office ??
        const OfficeConfig(
          name: 'Office',
          latitude: AppConfig.defaultOfficeLat,
          longitude: AppConfig.defaultOfficeLng,
          radiusMeters: AppConfig.defaultOfficeRadiusMeters,
        );
  }

  @override
  Future<TodayAttendanceStatus> getTodayStatus(String workDate) async {
    final cachedHistory = await cache.readAttendanceHistory();
    final outboxEvents = await outbox.getAllEvents();
    final merged = AttendanceRules.mergeHistoryWithOutbox(
      serverRecords: cachedHistory?.value ?? const [],
      outboxEvents: outboxEvents,
    );
    final todayRecord = merged.where((r) => r.date == workDate).firstOrNull;
    return todayRecord?.todayStatus ?? TodayAttendanceStatus.notCheckedIn;
  }

  @override
  Future<AttendanceEvent> enqueueEvent(AttendanceEvent event) {
    return outbox.enqueue(event);
  }
}
