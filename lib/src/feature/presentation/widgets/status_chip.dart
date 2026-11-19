import 'package:flutter/material.dart';

import '../../domain/models/attendance.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  factory StatusChip.sync(SyncStatus status) {
    return switch (status) {
      SyncStatus.pending => const StatusChip(
          label: 'Pending Sync',
          color: Color(0xFFD97706),
          icon: Icons.schedule,
        ),
      SyncStatus.synced => const StatusChip(
          label: 'Synced',
          color: Color(0xFF15803D),
          icon: Icons.cloud_done_outlined,
        ),
      SyncStatus.rejected => const StatusChip(
          label: 'Rejected',
          color: Color(0xFFB91C1C),
          icon: Icons.error_outline,
        ),
    };
  }

  factory StatusChip.today(TodayAttendanceStatus status) {
    return switch (status) {
      TodayAttendanceStatus.notCheckedIn => const StatusChip(
          label: 'Not Checked In',
          color: Color(0xFF64748B),
          icon: Icons.radio_button_unchecked,
        ),
      TodayAttendanceStatus.checkedIn => const StatusChip(
          label: 'Checked In',
          color: Color(0xFF15803D),
          icon: Icons.login,
        ),
      TodayAttendanceStatus.checkedOut => const StatusChip(
          label: 'Checked Out',
          color: Color(0xFF1D4ED8),
          icon: Icons.check_circle_outline,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
