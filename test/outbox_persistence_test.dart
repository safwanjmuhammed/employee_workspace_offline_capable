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

class _OrderedRecordingAdapter implements HttpClientAdapter {
  _OrderedRecordingAdapter({this.statusToReturn = 201});

  final int statusToReturn;
  final List<String> receivedTypes = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data as Map<String, dynamic>;
    receivedTypes.add(body['type'] as String);

    if (statusToReturn == 409) {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 'ATTENDANCE_EXISTS',
          'message': 'Attendance already recorded on server.',
        }),
        409,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'status': 'accepted',
        'replayed': false,
        'serverEventId': options.headers['Idempotency-Key'],
      }),
      statusToReturn,
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
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('emp_persist_test_');
    dbPath = p.join(tempDir.path, 'persist.db');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('pending check-in and check-out survive restart and sync in order',
      () async {
    final clock = SystemCompanyClock(
      timezoneName: 'Asia/Kolkata',
      nowProvider: () => DateTime.utc(2026, 11, 19, 4, 0),
    );
    final offline = _FakeConnectivity(false);

    // Session 1: create check-in and check-out while offline, then close DB.
    final db1 = await AppDatabase.open(
      customPath: dbPath,
      factory: databaseFactoryFfi,
    );
    final adapter1 = _OrderedRecordingAdapter();
    final service1 = AttendanceService(
      clock: clock,
      locationService: ConfigurableLocationService(
        modeProvider: () => LocationSimulationMode.insideOffice,
      ),
      cache: CacheStore(db1),
      outbox: OutboxStore(db1),
      syncEngine: SyncEngine(
        outbox: OutboxStore(db1),
        api: HrmsApi(
          DioApiService(
            dio: Dio(BaseOptions(baseUrl: 'http://localhost:8080'))
              ..httpClientAdapter = adapter1,
          ),
        ),
        connectivity: offline,
      ),
    );

    expect((await service1.performAction(AttendanceEventType.checkIn)).isSuccess,
        isTrue);
    expect(
        (await service1.performAction(AttendanceEventType.checkOut)).isSuccess,
        isTrue);
    await db1.close();

    // Session 2: reopen DB from disk, come online, and sync.
    final db2 = await AppDatabase.open(
      customPath: dbPath,
      factory: databaseFactoryFfi,
    );
    final outbox2 = OutboxStore(db2);
    expect(await outbox2.pendingCount(), 2);

    final adapter2 = _OrderedRecordingAdapter();
    final sync2 = SyncEngine(
      outbox: outbox2,
      api: HrmsApi(
        DioApiService(
          dio: Dio(BaseOptions(baseUrl: 'http://localhost:8080'))
            ..httpClientAdapter = adapter2,
        ),
      ),
      connectivity: _FakeConnectivity(true),
    );

    final summary = await sync2.syncPending();
    expect(summary.syncedCount, 2);
    expect(summary.remainingPendingCount, 0);
    expect(adapter2.receivedTypes, ['check_in', 'check_out']);

    final all = await outbox2.getAllEvents();
    expect(all.every((e) => e.syncStatus == SyncStatus.synced), isTrue);
    await db2.close();
  });

  test('409 conflict marks outbox event as rejected', () async {
    final db = await AppDatabase.open(
      customPath: dbPath,
      factory: databaseFactoryFfi,
    );
    final outbox = OutboxStore(db);
    await outbox.enqueue(
      AttendanceEvent(
        eventId: 'ev-409',
        type: AttendanceEventType.checkIn,
        workDate: '2026-11-19',
        occurredAtUtc: DateTime.utc(2026, 11, 19, 4, 0),
        latitude: 10.0101,
        longitude: 76.3637,
        accuracyMeters: 10,
        syncStatus: SyncStatus.pending,
        createdAtUtc: DateTime.utc(2026, 11, 19, 4, 0),
      ),
    );

    final adapter = _OrderedRecordingAdapter(statusToReturn: 409);
    final sync = SyncEngine(
      outbox: outbox,
      api: HrmsApi(
        DioApiService(
          dio: Dio(BaseOptions(baseUrl: 'http://localhost:8080'))
            ..httpClientAdapter = adapter,
        ),
      ),
      connectivity: _FakeConnectivity(true),
    );

    final summary = await sync.syncPending();
    expect(summary.rejectedCount, 1);
    expect(summary.remainingPendingCount, 0);

    final saved = (await outbox.getAllEvents()).single;
    expect(saved.syncStatus, SyncStatus.rejected);
    expect(saved.rejectReason, contains('already recorded'));
    await db.close();
  });
}
