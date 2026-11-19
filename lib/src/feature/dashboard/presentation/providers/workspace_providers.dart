import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_config.dart';
import '../../../../core/clock/company_clock.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/dio_api_service/api_service.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/network/connectivity_service.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../attendance/data/datasources/attendance_remote_datasource.dart';
import '../../../attendance/data/datasources/outbox_store.dart';
import '../../../attendance/data/repositories/attendance_repository_impl.dart';
import '../../../attendance/domain/models/attendance.dart';
import '../../../attendance/domain/repositories/attendance_repository.dart';
import '../../../attendance/domain/usecases/attendance_service.dart';
import '../../data/datasources/cache_store.dart';
import '../../data/datasources/dashboard_remote_datasource.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/models/dashboard_snapshot.dart';
import '../../domain/repositories/dashboard_repository.dart';

class DevSettings {
  const DevSettings({
    this.locationMode = LocationSimulationMode.realGps,
    this.simulateOffline = false,
    this.mockScenario = 'normal',
    this.baseUrl = AppConfig.baseUrl,
  });

  final LocationSimulationMode locationMode;
  final bool simulateOffline;
  final String mockScenario;
  final String baseUrl;

  DevSettings copyWith({
    LocationSimulationMode? locationMode,
    bool? simulateOffline,
    String? mockScenario,
    String? baseUrl,
  }) {
    return DevSettings(
      locationMode: locationMode ?? this.locationMode,
      simulateOffline: simulateOffline ?? this.simulateOffline,
      mockScenario: mockScenario ?? this.mockScenario,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}

class DevSettingsNotifier extends Notifier<DevSettings> {
  @override
  DevSettings build() => const DevSettings();

  void setLocationMode(LocationSimulationMode mode) {
    state = state.copyWith(locationMode: mode);
  }

  Future<void> setSimulateOffline(bool value) async {
    state = state.copyWith(simulateOffline: value);
    final connectivity = ref.read(connectivityServiceProvider);
    if (connectivity is AppConnectivityService) {
      await connectivity.notifySimulationChanged();
    }
  }

  void setMockScenario(String scenario) {
    state = state.copyWith(mockScenario: scenario);
  }

  void setBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    state = state.copyWith(baseUrl: trimmed);
    ref.read(dioApiServiceProvider).updateBaseUrl(trimmed);
  }
}

final devSettingsProvider =
    NotifierProvider<DevSettingsNotifier, DevSettings>(DevSettingsNotifier.new);

/// Overridden in `main()` with the opened SQLite database.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden at startup.');
});

final companyClockProvider = Provider<CompanyClock>((ref) {
  return SystemCompanyClock(timezoneName: AppConfig.companyTimezone);
});

final dioApiServiceProvider = Provider<DioApiService>((ref) {
  return DioApiService(
    baseUrl: ref.read(devSettingsProvider).baseUrl,
    isSimulatedOffline: () => ref.read(devSettingsProvider).simulateOffline,
    mockScenario: () => ref.read(devSettingsProvider).mockScenario,
  );
});

final dashboardRemoteDataSourceProvider =
    Provider<DashboardRemoteDataSource>((ref) {
  return DashboardRemoteDataSource(ref.watch(dioApiServiceProvider));
});

final attendanceRemoteDataSourceProvider =
    Provider<AttendanceRemoteDataSource>((ref) {
  return AttendanceRemoteDataSource(ref.watch(dioApiServiceProvider));
});

final cacheStoreProvider = Provider<CacheStore>((ref) {
  return CacheStore(ref.watch(databaseProvider));
});

final outboxStoreProvider = Provider<OutboxStore>((ref) {
  return OutboxStore(ref.watch(databaseProvider));
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepositoryImpl(
    cache: ref.watch(cacheStoreProvider),
    outbox: ref.watch(outboxStoreProvider),
  );
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return ConfigurableLocationService(
    modeProvider: () => ref.read(devSettingsProvider).locationMode,
  );
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = AppConnectivityService(
    isSimulatedOffline: () => ref.read(devSettingsProvider).simulateOffline,
  );
  ref.onDispose(service.dispose);
  return service;
});

final syncEngineProvider = Provider<SyncEngine<AttendanceEvent>>((ref) {
  return SyncEngine<AttendanceEvent>(
    outbox: ref.watch(outboxStoreProvider),
    transport: ref.watch(attendanceRemoteDataSourceProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

final attendanceServiceProvider = Provider<AttendanceService>((ref) {
  return AttendanceService(
    clock: ref.watch(companyClockProvider),
    locationService: ref.watch(locationServiceProvider),
    repository: ref.watch(attendanceRepositoryProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(
    clock: ref.watch(companyClockProvider),
    dashboardRemote: ref.watch(dashboardRemoteDataSourceProvider),
    attendanceRemote: ref.watch(attendanceRemoteDataSourceProvider),
    cache: ref.watch(cacheStoreProvider),
    outbox: ref.watch(outboxStoreProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

class WorkspaceController extends AsyncNotifier<WorkspaceSnapshot> {
  StreamSubscription<bool>? _connectivitySub;
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  @override
  Future<WorkspaceSnapshot> build() async {
    final connectivity = ref.watch(connectivityServiceProvider);
    _connectivitySub?.cancel();
    _connectivitySub = connectivity.onOnlineChanged.listen((online) {
      if (online) {
        syncNow();
      }
    });
    ref.onDispose(() {
      _connectivitySub?.cancel();
    });

    final repo = ref.read(dashboardRepositoryProvider);
    final online = await connectivity.isOnline();
    final cached = await repo.loadCachedSnapshot(isOffline: !online);

    if (cached != null) {
      unawaited(_syncAndRefreshQuietly());
      return cached;
    }

    final fresh = await repo.refreshFromRemote();
    unawaited(_syncPendingOnly());
    return fresh;
  }

  Future<void> _syncAndRefreshQuietly() async {
    await _syncPendingOnly();
    await refresh();
  }

  Future<void> _syncPendingOnly() async {
    try {
      await ref.read(syncEngineProvider).syncPending();
    } catch (_) {}
  }

  Future<void> refresh() async {
    final repo = ref.read(dashboardRepositoryProvider);
    try {
      final snapshot = await repo.refreshFromRemote();
      state = AsyncData(snapshot);
    } catch (e, st) {
      if (!state.hasValue) {
        state = AsyncError(e, st);
      }
    }
  }

  Future<void> reloadFromCache() async {
    final repo = ref.read(dashboardRepositoryProvider);
    final online = await ref.read(connectivityServiceProvider).isOnline();
    final cached = await repo.loadCachedSnapshot(isOffline: !online);
    if (cached != null) {
      state = AsyncData(cached);
    }
  }

  Future<AttendanceActionResult> performAttendanceAction(
    AttendanceEventType type,
  ) async {
    final result =
        await ref.read(attendanceServiceProvider).performAction(type);
    await reloadFromCache();
    return result;
  }

  Future<SyncSummary> syncNow() async {
    _isSyncing = true;
    try {
      final summary = await ref.read(syncEngineProvider).syncPending();
      await refresh();
      return summary;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> clearLocalData() async {
    await ref.read(databaseProvider).clearAll();
    state = const AsyncLoading();
    await refresh();
  }
}

final workspaceControllerProvider =
    AsyncNotifierProvider<WorkspaceController, WorkspaceSnapshot>(
  WorkspaceController.new,
);
