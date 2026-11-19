import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/workspace_repository.dart';
import '../providers/app_providers.dart';

class SyncStatusBar extends ConsumerStatefulWidget {
  const SyncStatusBar({super.key, required this.snapshot});

  final WorkspaceSnapshot snapshot;

  @override
  ConsumerState<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends ConsumerState<SyncStatusBar> {
  bool _syncing = false;

  Future<void> _onSyncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final summary =
          await ref.read(workspaceControllerProvider.notifier).syncNow();
      if (!mounted) return;
      final msg = summary.syncedCount > 0
          ? 'Synced ${summary.syncedCount} event(s).'
          : summary.rejectedCount > 0
              ? '${summary.rejectedCount} event(s) rejected by server.'
              : summary.lastError ?? 'Everything is up to date.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final clock = ref.watch(companyClockProvider);
    final updatedLabel = snap.lastUpdatedUtc != null
        ? DateFormat('HH:mm').format(clock.toCompanyTz(snap.lastUpdatedUtc!))
        : '--:--';

    final showBanner =
        snap.isOffline || snap.pendingCount > 0 || snap.rejectedCount > 0;
    if (!showBanner) return const SizedBox.shrink();

    final bgColor = snap.isOffline
        ? const Color(0xFFFEF3C7)
        : snap.rejectedCount > 0
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFE0F2FE);

    final fgColor = snap.isOffline
        ? const Color(0xFF92400E)
        : snap.rejectedCount > 0
            ? const Color(0xFF991B1B)
            : const Color(0xFF075985);

    final parts = <String>[];
    if (snap.isOffline) {
      parts.add('Offline (last updated $updatedLabel)');
    }
    if (snap.pendingCount > 0) {
      parts.add('${snap.pendingCount} pending sync');
    }
    if (snap.rejectedCount > 0) {
      parts.add('${snap.rejectedCount} rejected');
    }

    return Material(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              snap.isOffline ? Icons.cloud_off : Icons.sync_problem,
              size: 18,
              color: fgColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                parts.join(' • '),
                style: TextStyle(
                  color: fgColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _syncing ? null : _onSyncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 16),
              label: const Text('Sync Now'),
              style: TextButton.styleFrom(
                foregroundColor: fgColor,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
