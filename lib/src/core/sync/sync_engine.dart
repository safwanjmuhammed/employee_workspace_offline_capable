import '../dio_api_service/api_exception.dart';
import '../network/connectivity_service.dart';

abstract interface class SyncableEvent {
  String get eventId;
}

abstract interface class SyncOutbox<T extends SyncableEvent> {
  Future<List<T>> getPendingInOrder();
  Future<int> pendingCount();
  Future<void> markSynced(String eventId);
  Future<void> markRejected(String eventId, String reason);
  Future<void> recordAttemptFailure(String eventId, String error);
}

abstract interface class SyncTransport<T extends SyncableEvent> {
  Future<void> submit(T event);
}

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

/// Global outbox synchronization engine that drains pending events strictly
/// in sequence order. Depends only on core abstractions (zero feature imports).
class SyncEngine<T extends SyncableEvent> {
  SyncEngine({
    required this.outbox,
    required this.transport,
    required this.connectivity,
  });

  final SyncOutbox<T> outbox;
  final SyncTransport<T> transport;
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
        await transport.submit(event);
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
