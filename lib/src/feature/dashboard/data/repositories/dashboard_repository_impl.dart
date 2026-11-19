import '../../../../core/clock/company_clock.dart';
import '../../../../core/dio_api_service/api_exception.dart';
import '../../../../core/network/connectivity_service.dart';
import '../../../attendance/data/datasources/attendance_remote_datasource.dart';
import '../../../attendance/data/datasources/outbox_store.dart';
import '../../../attendance/domain/models/attendance.dart';
import '../../../attendance/domain/rules/attendance_rules.dart';
import '../../domain/models/dashboard_snapshot.dart';
import '../../domain/models/employee.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/cache_store.dart';
import '../datasources/dashboard_remote_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({
    required this.clock,
    required this.dashboardRemote,
    required this.attendanceRemote,
    required this.cache,
    required this.outbox,
    required this.connectivity,
  });

  final CompanyClock clock;
  final DashboardRemoteDataSource dashboardRemote;
  final AttendanceRemoteDataSource attendanceRemote;
  final CacheStore cache;
  final OutboxStore outbox;
  final ConnectivityService connectivity;

  @override
  Future<WorkspaceSnapshot?> loadCachedSnapshot({
    bool isOffline = false,
    String? remoteError,
  }) async {
    final emp = await cache.readEmployee();
    if (emp == null) return null;

    final hist = await cache.readAttendanceHistory();
    final events = await outbox.getAllEvents();

    final merged = AttendanceRules.mergeHistoryWithOutbox(
      serverRecords: hist?.value ?? const [],
      outboxEvents: events,
    );

    return WorkspaceSnapshot(
      employee: emp.value,
      mergedRecords: merged,
      outboxEvents: events,
      lastUpdatedUtc: emp.updatedAtUtc,
      isOffline: isOffline,
      remoteError: remoteError,
    );
  }

  @override
  Future<WorkspaceSnapshot> refreshFromRemote() async {
    final online = await connectivity.isOnline();
    if (!online) {
      final cached = await loadCachedSnapshot(isOffline: true);
      if (cached != null) return cached;
      throw const ApiException(
        kind: ApiErrorKind.offline,
        message: 'You are offline and no cached workspace data is available yet.',
      );
    }

    final companyNow = clock.nowInCompanyTz();
    final month =
        '${companyNow.year.toString().padLeft(4, '0')}-${companyNow.month.toString().padLeft(2, '0')}';

    try {
      final results = await Future.wait([
        dashboardRemote.fetchEmployee(),
        attendanceRemote.fetchAttendance(month),
      ]);

      final employee = results[0] as Employee;
      final records = results[1] as List<AttendanceRecord>;
      final nowUtc = clock.nowUtc();

      await Future.wait([
        cache.saveEmployee(employee, nowUtc),
        cache.saveAttendanceHistory(records, nowUtc),
      ]);

      final events = await outbox.getAllEvents();
      final merged = AttendanceRules.mergeHistoryWithOutbox(
        serverRecords: records,
        outboxEvents: events,
      );

      return WorkspaceSnapshot(
        employee: employee,
        mergedRecords: merged,
        outboxEvents: events,
        lastUpdatedUtc: nowUtc,
        isOffline: false,
      );
    } on ApiException catch (e) {
      final cached = await loadCachedSnapshot(
        isOffline:
            e.kind == ApiErrorKind.offline || e.kind == ApiErrorKind.network,
        remoteError: e.message,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }
}
