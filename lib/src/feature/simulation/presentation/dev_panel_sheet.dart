import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_service.dart';
import '../../dashboard/presentation/providers/workspace_providers.dart';

class DevPanelSheet extends ConsumerStatefulWidget {
  const DevPanelSheet({super.key});

  @override
  ConsumerState<DevPanelSheet> createState() => _DevPanelSheetState();
}

class _DevPanelSheetState extends ConsumerState<DevPanelSheet> {
  late final TextEditingController _urlController;

  static const _scenarios = <String, String>{
    'normal': 'Normal (200 / 201)',
    'slow': 'Slow (~3 s delay)',
    'timeout': 'Timeout (>10 s hang)',
    'server_error': 'Server Error (500)',
    'duplicate_attendance': 'Duplicate Attendance (409)',
    'attendance_rejected': 'Attendance Rejected (422)',
    'replay': 'Idempotent Replay (200 replayed:true)',
  };

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(devSettingsProvider).baseUrl,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(devSettingsProvider);
    final notifier = ref.read(devSettingsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Simulation & Testing Controls',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Simulate Offline'),
                subtitle: const Text(
                  'Short-circuits network calls and triggers offline queue.',
                ),
                value: settings.simulateOffline,
                onChanged: (v) async {
                  await notifier.setSimulateOffline(v);
                  await ref
                      .read(workspaceControllerProvider.notifier)
                      .reloadFromCache();
                },
              ),
              const Divider(),
              Text(
                'Location Simulation',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<LocationSimulationMode>(
                initialValue: settings.locationMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: LocationSimulationMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.label),
                      ),
                    )
                    .toList(),
                onChanged: (m) {
                  if (m != null) notifier.setLocationMode(m);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Mock API Scenario (X-Mock-Scenario)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: settings.mockScenario,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _scenarios.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) notifier.setMockScenario(s);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Mock API Base URL',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'http://10.0.2.2:8080',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      notifier.setBaseUrl(_urlController.text);
                      ref.read(workspaceControllerProvider.notifier).refresh();
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await ref
                        .read(workspaceControllerProvider.notifier)
                        .clearLocalData();
                    if (mounted) nav.pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Local Cache & Outbox'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
