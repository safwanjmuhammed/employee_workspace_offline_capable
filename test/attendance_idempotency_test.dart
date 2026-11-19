import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:employee_workspace_offline_capable/src/core/clock/company_clock.dart';
import 'package:employee_workspace_offline_capable/src/core/db/app_database.dart';
import 'package:employee_workspace_offline_capable/src/core/dio_api_service/api_service.dart';
import 'package:employee_workspace_offline_capable/src/core/location/location_service.dart';
import 'package:employee_workspace_offline_capable/src/core/network/connectivity_service.dart';
import 'package:employee_workspace_offline_capable/src/feature/data/local/cache_store.dart';
import 'package:employee_workspace_offline_capable/src/feature/data/local/outbox_store.dart';
import 'package:employee_workspace_offline_capable/src/feature/data/remote/hrms_api.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/models/attendance.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/services/attendance_service.dart';
import 'package:employee_workspace_offline_capable/src/feature/domain/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this.online);
  bool online;

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onOnlineChanged => const Stream.empty();
}

/// Simulates a server that commits on attempt 1 then times out before replying,
/// and replays the committed result on retry with the same Idempotency-Key.
class _AcceptThenTimeoutAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> serverRecords = [];
  final Set<String> seenKeys = {};
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    final key = options.headers['Idempotency-Key']?.toString() ?? '';
    final body = options.data as Map<String, dynamic>;

    if (!seenKeys.contains(key)) {
      seenKeys.add(key);
      serverRecords.add(body);
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
        message: 'Simulated timeout after server commit',
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'status': 'accepted',
        'replayed': true,
        'serverEventId': key,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emp_idem_test_');
    db = await AppDatabase.open(
      customPath: p.join(tempDir.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('repeated taps and retry after timeout produce a single server record',
      () async {
    final adapter = _AcceptThenTimeoutAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'))
      ..httpClientAdapter = adapter;

    final connectivity = _FakeConnectivity(false);
    final clock = SystemCompanyClock(
      timezoneName: 'Asia/Kolkata',
      nowProvider: () => DateTime.utc(2026, 11, 19, 4, 0),
    );
    final cache = CacheStore(db);
    final outbox = OutboxStore(db);
    final api = HrmsApi(DioApiService(dio: dio));
    final syncEngine = SyncEngine(
      outbox: outbox,
      api: api,
      connectivity: connectivity,
    );
    final attendance = AttendanceService(
      clock: clock,
      locationService: ConfigurableLocationService(
        modeProvider: () => LocationSimulationMode.insideOffice,
      ),
      cache: cache,
      outbox: outbox,
      syncEngine: syncEngine,
    );

    // First tap while offline -> saved to outbox.
    final first = await attendance.performAction(AttendanceEventType.checkIn);
    expect(first.isSuccess, isTrue);

    // Second tap on the same day -> rejected, no duplicate outbox row.
    final second = await attendance.performAction(AttendanceEventType.checkIn);
    expect(second.isSuccess, isFalse);
    expect((await outbox.getAllEvents()).length, 1);

    // Connectivity returns, attempt 1 commits on server then times out.
    connectivity.online = true;
    final firstSync = await syncEngine.syncPending();
    expect(firstSync.stoppedOnTransientError, isTrue);
    expect(firstSync.remainingPendingCount, 1);
    expect(adapter.serverRecords.length, 1);

    // Retry sends the same Idempotency-Key -> server replays 200, no duplicate.
    final retrySync = await syncEngine.syncPending();
    expect(retrySync.syncedCount, 1);
    expect(retrySync.remainingPendingCount, 0);
    expect(adapter.serverRecords.length, 1);
    expect(adapter.callCount, 2);

    final events = await outbox.getAllEvents();
    expect(events.single.syncStatus, SyncStatus.synced);
  });
}
