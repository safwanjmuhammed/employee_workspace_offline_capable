import '../../../core/dio_api_service/api_exception.dart';
import '../../../core/network/connectivity_service.dart';
import '../../data/local/outbox_store.dart';
import '../../data/remote/hrms_api.dart';

class SyncSummary {
  const SyncSummary({
    required this.syncedCount,
    required this.rejectedCount,
    required this.remainingPendingCount,
    required this.stoppedOnTransientError,
    this.lastError,
  });

  final int syncedCount;
  final int rejectedCount;
  final int remainingPendingCount;
  final bool stoppedOnTransientError;
  final String? lastError;
}

/// Synchronizes pending attendance outbox events strictly in sequence order.
class SyncEngine {
  SyncEngine({
    required this.outbox,
    required this.api,
    required this.connectivity,
  });

  final OutboxStore outbox;
  final HrmsApi api;
  final ConnectivityService connectivity;

  Future<SyncSummary>? _inFlight;

  bool get isSyncing => _inFlight != null;

  Future<SyncSummary> syncPending() {
    return _inFlight ??= _run().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<SyncSummary> _run() async {
    final pending = await outbox.getPendingInOrder();
    if (pending.isEmpty) {
      return const SyncSummary(
        syncedCount: 0,
        rejectedCount: 0,
        remainingPendingCount: 0,
        stoppedOnTransientError: false,
      );
    }

    if (!await connectivity.isOnline()) {
      return SyncSummary(
        syncedCount: 0,
        rejectedCount: 0,
        remainingPendingCount: pending.length,
        stoppedOnTransientError: true,
        lastError: 'Device is offline.',
      );
    }

    var synced = 0;
    var rejected = 0;
    var stoppedTransient = false;
    String? lastError;

    for (final event in pending) {
      try {
        await api.submitAttendanceEvent(event);
        await outbox.markSynced(event.eventId);
        synced++;
      } on ApiException catch (e) {
        if (e.kind == ApiErrorKind.conflict ||
            e.kind == ApiErrorKind.validation) {
          await outbox.markRejected(event.eventId, e.message);
          rejected++;
          lastError = e.message;
        } else {
          // Transient error (offline, timeout, 5xx, network): stop immediately
          // to preserve strict check-in -> check-out ordering.
          await outbox.recordAttemptFailure(event.eventId, e.message);
          stoppedTransient = true;
          lastError = e.message;
          break;
        }
      } catch (e) {
        await outbox.recordAttemptFailure(event.eventId, e.toString());
        stoppedTransient = true;
        lastError = e.toString();
        break;
      }
    }

    final remaining = await outbox.pendingCount();
    return SyncSummary(
      syncedCount: synced,
      rejectedCount: rejected,
      remainingPendingCount: remaining,
      stoppedOnTransientError: stoppedTransient,
      lastError: lastError,
    );
  }
}
