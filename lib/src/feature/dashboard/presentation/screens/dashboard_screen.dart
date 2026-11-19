import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../common/atom/status_chip.dart';
import '../../../../common/molecule/sync_status_bar.dart';
import '../../../../core/clock/company_clock.dart';
import '../../../attendance/domain/models/attendance.dart';
import '../../../attendance/domain/usecases/attendance_service.dart';
import '../../domain/models/dashboard_snapshot.dart';
import '../providers/workspace_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenHistory;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _actionBusy = false;
  Timer? _ticker;
  DateTime _nowUtc = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _nowUtc = ref.read(companyClockProvider).nowUtc();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _handleAttendance(AttendanceEventType type) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final result = await ref
          .read(workspaceControllerProvider.notifier)
          .performAttendanceAction(type);
      if (!mounted) return;
      _showActionFeedback(result);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showActionFeedback(AttendanceActionResult result) {
    final msg = result.message ?? 'Done';
    if (result.outcome == AttendanceActionOutcome.permissionPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              ref.read(locationServiceProvider).openAppSettings();
            },
          ),
        ),
      );
      return;
    }

    if (result.outcome == AttendanceActionOutcome.locationServiceDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: 'Enable GPS',
            onPressed: () {
              ref.read(locationServiceProvider).openLocationSettings();
            },
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final asyncSnap = ref.watch(workspaceControllerProvider);
    final clock = ref.watch(companyClockProvider);

    return asyncSnap.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading employee workspace...'),
            ],
          ),
        ),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Unable to load workspace',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                err.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(workspaceControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (snap) => _buildContent(context, snap, clock),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WorkspaceSnapshot snap,
    CompanyClock clock,
  ) {
    final todayDate = clock.todayWorkDate();
    final todayRecord = snap.todayRecord(todayDate);
    final todayStatus =
        todayRecord?.todayStatus ?? TodayAttendanceStatus.notCheckedIn;
    final elapsed = todayRecord?.elapsedDuration(_nowUtc);

    return Column(
      children: [
        SyncStatusBar(snapshot: snap),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(workspaceControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _EmployeeHeaderCard(snap: snap),
                const SizedBox(height: 12),
                _TodayAttendanceCard(
                  todayStatus: todayStatus,
                  todayRecord: todayRecord,
                  elapsed: elapsed,
                  clock: clock,
                  actionBusy: _actionBusy,
                  onCheckIn: () =>
                      _handleAttendance(AttendanceEventType.checkIn),
                  onCheckOut: () =>
                      _handleAttendance(AttendanceEventType.checkOut),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Latest Attendance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: widget.onOpenHistory,
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (snap.latestFiveRecords.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text('No attendance records available yet.'),
                      ),
                    ),
                  )
                else
                  ...snap.latestFiveRecords.map(
                    (rec) => _AttendanceRecordTile(record: rec, clock: clock),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeHeaderCard extends StatelessWidget {
  const _EmployeeHeaderCard({required this.snap});
  final WorkspaceSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final emp = snap.employee;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Text(
                emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'E',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emp.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${emp.id} • ${emp.department}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${emp.office.name} (${emp.companyTimezone})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayAttendanceCard extends StatelessWidget {
  const _TodayAttendanceCard({
    required this.todayStatus,
    required this.todayRecord,
    required this.elapsed,
    required this.clock,
    required this.actionBusy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final TodayAttendanceStatus todayStatus;
  final AttendanceRecord? todayRecord;
  final Duration? elapsed;
  final CompanyClock clock;
  final bool actionBusy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  String _formatTime(DateTime? utc) {
    if (utc == null) return '--:--';
    return DateFormat('hh:mm a').format(clock.toCompanyTz(utc));
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '00h 00m 00s';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final canCheckIn = todayStatus == TodayAttendanceStatus.notCheckedIn;
    final canCheckOut = todayStatus == TodayAttendanceStatus.checkedIn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  "Today's Attendance",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                StatusChip.today(todayStatus),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricColumn(
                    label: 'Check-In',
                    value: _formatTime(todayRecord?.checkInAtUtc),
                    syncStatus: todayRecord?.checkInSyncStatus,
                  ),
                ),
                Expanded(
                  child: _MetricColumn(
                    label: 'Check-Out',
                    value: _formatTime(todayRecord?.checkOutAtUtc),
                    syncStatus: todayRecord?.checkOutSyncStatus,
                  ),
                ),
                Expanded(
                  child: _MetricColumn(
                    label: 'Elapsed',
                    value: _formatDuration(elapsed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: actionBusy
                    ? null
                    : canCheckIn
                        ? onCheckIn
                        : canCheckOut
                            ? onCheckOut
                            : null,
                icon: actionBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        canCheckIn
                            ? Icons.login
                            : canCheckOut
                                ? Icons.logout
                                : Icons.check_circle,
                      ),
                label: Text(
                  canCheckIn
                      ? 'Check In'
                      : canCheckOut
                          ? 'Check Out'
                          : 'Completed for Today',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    this.syncStatus,
  });

  final String label;
  final String value;
  final SyncStatus? syncStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (syncStatus != null) ...[
          const SizedBox(height: 4),
          StatusChip.sync(syncStatus!),
        ],
      ],
    );
  }
}

class _AttendanceRecordTile extends StatelessWidget {
  const _AttendanceRecordTile({required this.record, required this.clock});

  final AttendanceRecord record;
  final CompanyClock clock;

  String _fmt(DateTime? utc) {
    if (utc == null) return '--:--';
    return DateFormat('hh:mm a').format(clock.toCompanyTz(utc));
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = record.checkOutSyncStatus ?? record.checkInSyncStatus;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          record.date,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'In: ${_fmt(record.checkInAtUtc)}  •  Out: ${_fmt(record.checkOutAtUtc)}',
        ),
        trailing: syncStatus != null ? StatusChip.sync(syncStatus) : null,
      ),
    );
  }
}
