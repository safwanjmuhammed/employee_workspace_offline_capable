import '../../../core/clock/company_clock.dart';
import '../../../core/dio_api_service/api_exception.dart';
import '../../../core/network/connectivity_service.dart';
import '../../domain/models/attendance.dart';
import '../../domain/models/employee.dart';
import '../../domain/rules/attendance_rules.dart';
import '../local/cache_store.dart';
import '../local/outbox_store.dart';
import '../remote/hrms_api.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.employee,
    required this.mergedRecords,
    required this.outboxEvents,
    required this.lastUpdatedUtc,
    required this.isOffline,
    this.remoteError,
  });

  final Employee employee;
  final List<AttendanceRecord> mergedRecords;
  final List<AttendanceEvent> outboxEvents;
  final DateTime? lastUpdatedUtc;
  final bool isOffline;
  final String? remoteError;

  int get pendingCount =>
      outboxEvents.where((e) => e.syncStatus == SyncStatus.pending).length;

  int get rejectedCount =>
      outboxEvents.where((e) => e.syncStatus == SyncStatus.rejected).length;

  AttendanceRecord? todayRecord(String todayWorkDate) {
    for (final r in mergedRecords) {
      if (r.date == todayWorkDate) return r;
    }
    return null;
  }

  List<AttendanceRecord> get latestFiveRecords =>
      mergedRecords.take(5).toList();
}

class WorkspaceRepository {
  WorkspaceRepository({
    required CompanyClock clock,
    required HrmsApi api,
    required CacheStore cache,
    required OutboxStore outbox,
    required ConnectivityService connectivity,
  })  : _clock = clock,
        _api = api,
        _cache = cache,
        _outbox = outbox,
        _connectivity = connectivity;

  final CompanyClock _clock;
  final HrmsApi _api;
  final CacheStore _cache;
  final OutboxStore _outbox;
  final ConnectivityService _connectivity;

  Future<WorkspaceSnapshot?> loadCachedSnapshot({
    bool isOffline = false,
    String? remoteError,
  }) async {
    final emp = await _cache.readEmployee();
    if (emp == null) return null;

    final hist = await _cache.readAttendanceHistory();
    final outbox = await _outbox.getAllEvents();

    final merged = AttendanceRules.mergeHistoryWithOutbox(
      serverRecords: hist?.value ?? const [],
      outboxEvents: outbox,
    );

    return WorkspaceSnapshot(
      employee: emp.value,
      mergedRecords: merged,
      outboxEvents: outbox,
      lastUpdatedUtc: emp.updatedAtUtc,
      isOffline: isOffline,
      remoteError: remoteError,
    );
  }

  Future<WorkspaceSnapshot> refreshFromRemote() async {
    final online = await _connectivity.isOnline();
    if (!online) {
      final cached = await loadCachedSnapshot(isOffline: true);
      if (cached != null) return cached;
      throw const ApiException(
        kind: ApiErrorKind.offline,
        message: 'You are offline and no cached workspace data is available yet.',
      );
    }

    final companyNow = _clock.nowInCompanyTz();
    final month =
        '${companyNow.year.toString().padLeft(4, '0')}-${companyNow.month.toString().padLeft(2, '0')}';

    try {
      final results = await Future.wait([
        _api.fetchEmployee(),
        _api.fetchAttendance(month),
      ]);

      final employee = results[0] as Employee;
      final records = results[1] as List<AttendanceRecord>;
      final nowUtc = _clock.nowUtc();

      await Future.wait([
        _cache.saveEmployee(employee, nowUtc),
        _cache.saveAttendanceHistory(records, nowUtc),
      ]);

      final outbox = await _outbox.getAllEvents();
      final merged = AttendanceRules.mergeHistoryWithOutbox(
        serverRecords: records,
        outboxEvents: outbox,
      );

      return WorkspaceSnapshot(
        employee: employee,
        mergedRecords: merged,
        outboxEvents: outbox,
        lastUpdatedUtc: nowUtc,
        isOffline: false,
      );
    } on ApiException catch (e) {
      final cached = await loadCachedSnapshot(
        isOffline: e.kind == ApiErrorKind.offline || e.kind == ApiErrorKind.network,
        remoteError: e.message,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }
}
