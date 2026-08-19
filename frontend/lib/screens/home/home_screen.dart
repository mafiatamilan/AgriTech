import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/backend.dart';
import '../../widgets/shared.dart';
import '../../widgets/weather_card.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onNavigate,
    required this.onOpenDrawer,
  });

  final void Function(int index) onNavigate;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final farms = ref.watch(farmsProvider);
    final farm = farms.currentFarm;
    final farmId = farm?.id;

    // In-app alert when a new notification row lands (realtime).
    ref.listen(realtimeController, (prev, next) {
      if (next > (prev ?? 0)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.homeNotifications)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: onOpenDrawer,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref, farmId),
        child: ListView(
          children: [
            const FarmSwitcher(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.homeWelcome(ref.watch(authProvider).profile?.name ?? ''),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (farmId == null)
              const SizedBox.shrink()
            else ...[
              _KpiGrid(
                waterSaved: ref.watch(waterSavedProvider),
                motorStatus: ref.watch(motorStatusProvider(farmId)),
                notifications: ref.watch(notificationsProvider),
                impact: ref.watch(impactProvider(farmId)),
              ),
              WeatherCard(provider: ref.watch(farmWeatherProvider(farmId))),
              _SignalCard(provider: ref.watch(motorStatusProvider(farmId))),
            ],
            _NotificationsPreview(provider: ref.watch(notificationsProvider)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref, String? farmId) async {
    ref.invalidate(waterSavedProvider);
    ref.invalidate(notificationsProvider);
    if (farmId != null) {
      ref.invalidate(motorStatusProvider(farmId));
      ref.invalidate(farmWeatherProvider(farmId));
      ref.read(farmsProvider.notifier).load();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.waterSaved,
    required this.motorStatus,
    required this.notifications,
    required this.impact,
  });

  final AsyncValue<WaterSaved> waterSaved;
  final AsyncValue<OfflineResult<MotorStatus>> motorStatus;
  final AsyncValue<List<AppNotification>> notifications;
  final AsyncValue<ImpactMetrics> impact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final water = waterSaved.value?.totalLiters ?? 0;
    final motor = motorStatus.value?.data;
    final latestMoisture = motor?.moistureReadings.isEmpty ?? true
        ? null
        : motor!.moistureReadings.first.moisturePct;
    final motorOn =
        motor?.motorRelayState == true || motor?.currentStatus != null;
    final unreadAlerts =
        notifications.value?.where((n) => !n.isRead).length ?? 0;
    final impactCount =
        (impact.value?.precisionAgriculture.length ?? 0) +
        (impact.value?.circularSupplyChain.length ?? 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.55,
        children: [
          _KpiTile(
            icon: Icons.water_drop_outlined,
            label: l10n.homeWaterSaved,
            value: '${water.toStringAsFixed(1)} ${l10n.homeLiters}',
            color: const Color(0xFF1976D2),
          ),
          _KpiTile(
            icon: motorOn ? Icons.power : Icons.power_off_outlined,
            label: l10n.homeMotorState,
            value: motorOn ? l10n.motorRunning : l10n.motorIdle,
            color: motorOn ? const Color(0xFF2E7D32) : Colors.grey.shade700,
          ),
          _KpiTile(
            icon: Icons.grass_outlined,
            label: l10n.motorSoilMoisture,
            value: latestMoisture == null
                ? l10n.homeNoSignal
                : '${latestMoisture.toStringAsFixed(1)}%',
            color: const Color(0xFF00897B),
          ),
          _KpiTile(
            icon: unreadAlerts > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            label: l10n.homeNotifications,
            value: unreadAlerts.toString(),
            color: unreadAlerts > 0
                ? Colors.orange.shade800
                : Colors.grey.shade700,
          ),
          _KpiTile(
            icon: Icons.insights_outlined,
            label: l10n.navImpact,
            value: impactCount.toString(),
            color: const Color(0xFF6A1B9A),
          ),
          _KpiTile(
            icon: Icons.agriculture_outlined,
            label: l10n.navRecommendations,
            value: impact.isLoading || motorStatus.isLoading ? '...' : 'Live',
            color: const Color(0xFF795548),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
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

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.provider});

  final AsyncValue<OfflineResult<MotorStatus>> provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = provider.value;
    final signal = result?.data.signalStrength;
    final relay = result?.data.motorRelayState;
    final isRunning = result?.data.currentStatus != null;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result?.fromCache ?? false)
            StaleBanner(savedAt: result!.savedAt!),
          ListTile(
            leading: const Icon(Icons.sensors),
            title: Text(l10n.homeSignalStrength),
            subtitle: Text(
              signal == null
                  ? l10n.homeNoSignal
                  : '${signal < 0 ? signal : -signal} dBm',
              style: TextStyle(
                color: signal == null ? Colors.grey : _signalColor(signal),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              relay == true || isRunning
                  ? Icons.power
                  : Icons.power_off_outlined,
              color: relay == true || isRunning ? Colors.blue : null,
            ),
            title: Text(l10n.homeMotorState),
            subtitle: Text(
              relay == true
                  ? l10n.motorRunning
                  : relay == false
                  ? l10n.motorIdle
                  : l10n.homeNoSignal,
            ),
          ),
        ],
      ),
    );
  }

  Color _signalColor(int signal) {
    if (signal > -70) return Colors.green;
    if (signal > -90) return Colors.orange;
    return Colors.red;
  }
}

class _NotificationsPreview extends ConsumerWidget {
  const _NotificationsPreview({required this.provider});

  final AsyncValue<List<AppNotification>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = provider.value ?? const [];
    final preview = items.take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.homeNotifications,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                  child: Text(l10n.homeViewAll),
                ),
              ],
            ),
            if (preview.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.homeNoNotifications),
              )
            else
              for (final n in preview)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_typeIcon(n.type), size: 20),
                  title: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    n.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _timeAgo(n.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'watering':
        return Icons.water_drop;
      case 'match':
      case 'sale_confirmed':
        return Icons.storefront;
      default:
        return Icons.notifications;
    }
  }

  String _timeAgo(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return DateFormat('dd MMM').format(d);
  }
}
