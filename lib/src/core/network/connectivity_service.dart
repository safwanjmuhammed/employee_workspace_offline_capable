import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports effective connectivity by combining platform [Connectivity] with
/// the developer "Simulate Offline" toggle.
abstract interface class ConnectivityService {
  Future<bool> isOnline();
  Stream<bool> get onOnlineChanged;
}

class AppConnectivityService implements ConnectivityService {
  AppConnectivityService({
    required this.isSimulatedOffline,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _emit(_hasNetwork(results) && !isSimulatedOffline());
    });
  }

  final bool Function() isSimulatedOffline;
  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _emit(bool online) {
    if (!_controller.isClosed) {
      _controller.add(online);
    }
  }

  /// Called by the Dev Panel whenever the simulated-offline switch changes.
  Future<void> notifySimulationChanged() async {
    _emit(await isOnline());
  }

  @override
  Future<bool> isOnline() async {
    if (isSimulatedOffline()) return false;
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasNetwork(results);
    } catch (_) {
      return true;
    }
  }

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
