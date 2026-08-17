import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class MotorScreen extends ConsumerStatefulWidget {
  const MotorScreen({super.key});

  @override
  ConsumerState<MotorScreen> createState() => _MotorScreenState();
}

class _MotorScreenState extends ConsumerState<MotorScreen> {
  bool _motorOnBusy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final farmId = ref.watch(farmsProvider).currentFarm?.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMotor)),
      body: farmId == null
          ? Center(child: Text(l10n.homeNoFarm))
          : ref.watch(motorStatusProvider(farmId)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                onRetry: () => ref.invalidate(motorStatusProvider(farmId)),
              ),
              data: (result) => ListView(
                children: [
                  const FarmSwitcher(),
                  if (result.fromCache) StaleBanner(savedAt: result.savedAt!),
                  _StatusCards(status: result.data),
                  _MoistureCard(status: result.data),
                  _ActionsCard(
                    status: result.data,
                    motorOnBusy: _motorOnBusy,
                    onStop: () => _action(farmId, l10n.motorStopCurrent,
                        () => ref.read(backendProvider).stopCurrent(farmId)),
                    onCancelNext: () => _action(
                        farmId, l10n.motorCancelNext,
                        () => ref.read(backendProvider).cancelNext(farmId)),
                    onMotorOn: () => _motorOn(farmId),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _action(String farmId, String verb, Future<void> Function() call) async {
    try {
      await call();
      ref.invalidate(motorStatusProvider(farmId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$verb ✓')));
      }
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _motorOn(String farmId) async {
    // Optimistic disable: the relay flips asynchronously via the
    // hardware command-dispatch path.
    setState(() => _motorOnBusy = true);
    await _action(farmId, 'Motor ON', () => ref.read(backendProvider).motorOn(farmId));
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _motorOnBusy = false);
  }
}

class _StatusCards extends StatelessWidget {
  const _StatusCards({required this.status});

  final MotorStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRunning = status.currentStatus != null;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.motorLastWatered),
            subtitle: Text(
              status.lastWatered?.stoppedAt != null
                  ? fmtDate(status.lastWatered!.stoppedAt)
                  : l10n.motorNever,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l10n.motorNextWatering),
            subtitle: Text(
              status.nextWatering?.scheduledTime != null
                  ? fmtDate(status.nextWatering!.scheduledTime)
                  : l10n.motorNever,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              isRunning ? Icons.water_drop : Icons.water_drop_outlined,
              color: isRunning ? Colors.blue : null,
            ),
            title: Text(
              isRunning ? l10n.motorRunning : l10n.motorIdle,
              style: isRunning
                  ? const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)
                  : null,
            ),
            subtitle: status.currentStatus?.startedAt != null
                ? Text('${l10n.motorRunning} · ${fmtDate(status.currentStatus!.startedAt)}')
                : null,
          ),
        ],
      ),
    );
  }
}

class _MoistureCard extends StatelessWidget {
  const _MoistureCard({required this.status});

  final MotorStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.motorSoilMoisture,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            moistureLineChart(status.moistureReadings),
          ],
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.status,
    required this.motorOnBusy,
    required this.onStop,
    required this.onCancelNext,
    required this.onMotorOn,
  });

  final MotorStatus status;
  final bool motorOnBusy;
  final VoidCallback onStop;
  final VoidCallback onCancelNext;
  final VoidCallback onMotorOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canStop = status.currentStatus != null;
    final canCancel = status.nextWatering != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            OutlinedButton.icon(
              onPressed: canStop ? onStop : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(l10n.motorStopCurrent),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: canCancel ? onCancelNext : null,
              icon: const Icon(Icons.event_busy),
              label: Text(l10n.motorCancelNext),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: motorOnBusy ? null : onMotorOn,
              icon: const Icon(Icons.power),
              label: Text(l10n.motorOn),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ),
      ),
    );
  }
}