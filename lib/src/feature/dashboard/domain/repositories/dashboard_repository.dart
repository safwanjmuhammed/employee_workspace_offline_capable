import '../models/dashboard_snapshot.dart';

/// Domain repository contract for loading cached or refreshed dashboard data.
abstract interface class DashboardRepository {
  Future<WorkspaceSnapshot?> loadCachedSnapshot({
    bool isOffline = false,
    String? remoteError,
  });

  Future<WorkspaceSnapshot> refreshFromRemote();
}
