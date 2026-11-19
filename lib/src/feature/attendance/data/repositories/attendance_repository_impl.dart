import '../../../../config/app_config.dart';
import '../../../dashboard/data/datasources/cache_store.dart';
import '../../../dashboard/domain/models/employee.dart';
import '../../domain/models/attendance.dart';
import '../../domain/repositories/attendance_repository.dart';
import '../../domain/rules/attendance_rules.dart';
import '../datasources/outbox_store.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  AttendanceRepositoryImpl({
    required CacheStore cache,
    required OutboxStore outbox,
  }) : _cache = cache,
       _outbox = outbox;

  final CacheStore _cache;
  final OutboxStore _outbox;

  @override
  Future<OfficeConfig> getOfficeConfig() async {
    final cachedEmployee = await _cache.readEmployee();
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
    final cachedHistory = await _cache.readAttendanceHistory();
    final outboxEvents = await _outbox.getAllEvents();
    final merged = AttendanceRules.mergeHistoryWithOutbox(
      serverRecords: cachedHistory?.value ?? const [],
      outboxEvents: outboxEvents,
    );
    final todayRecord = merged.where((r) => r.date == workDate).firstOrNull;
    return todayRecord?.todayStatus ?? TodayAttendanceStatus.notCheckedIn;
  }

  @override
  Future<AttendanceEvent> enqueueEvent(AttendanceEvent event) {
    return _outbox.enqueue(event);
  }
}
