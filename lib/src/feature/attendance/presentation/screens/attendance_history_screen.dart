import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../common/atom/status_chip.dart';
import '../../../../common/molecule/sync_status_bar.dart';
import '../../../../core/clock/company_clock.dart';
import '../../../dashboard/presentation/providers/workspace_providers.dart';
import '../../domain/models/attendance.dart';

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnap = ref.watch(workspaceControllerProvider);
    final clock = ref.watch(companyClockProvider);

    return asyncSnap.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text(err.toString())),
      data: (snap) {
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              SyncStatusBar(snapshot: snap),
              const TabBar(
                tabs: [
                  Tab(text: 'Attendance Log'),
                  Tab(text: 'Sync Outbox'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _HistoryList(records: snap.mergedRecords, clock: clock),
                    _OutboxList(events: snap.outboxEvents, clock: clock),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records, required this.clock});

  final List<AttendanceRecord> records;
  final CompanyClock clock;

  String _fmt(DateTime? utc) {
    if (utc == null) return '--:--';
    return DateFormat('hh:mm a').format(clock.toCompanyTz(utc));
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(child: Text('No attendance records yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final rec = records[index];
        final syncStatus = rec.checkOutSyncStatus ?? rec.checkInSyncStatus;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              rec.date,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'In: ${_fmt(rec.checkInAtUtc)}  •  Out: ${_fmt(rec.checkOutAtUtc)}',
            ),
            trailing: syncStatus != null ? StatusChip.sync(syncStatus) : null,
          ),
        );
      },
    );
  }
}

class _OutboxList extends StatelessWidget {
  const _OutboxList({required this.events, required this.clock});

  final List<AttendanceEvent> events;
  final CompanyClock clock;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('No local check-in/check-out events queued yet.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final ev = events[index];
        final timeStr = DateFormat('yyyy-MM-dd hh:mm a')
            .format(clock.toCompanyTz(ev.occurredAtUtc));
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${ev.type.label} (${ev.workDate})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    StatusChip.sync(ev.syncStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Captured: $timeStr'),
                Text(
                  'ID: ${ev.eventId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (ev.rejectReason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Rejected: ${ev.rejectReason}',
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ] else if (ev.lastError != null &&
                    ev.syncStatus == SyncStatus.pending) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last attempt (${ev.attempts}): ${ev.lastError}',
                    style: const TextStyle(color: Color(0xFFD97706)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
