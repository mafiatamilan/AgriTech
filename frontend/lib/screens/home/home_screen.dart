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
        actions: [
          IconButton(
            tooltip: l10n.homeNotifications,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref, farmId),
        child: ListView(
          children: [
            const FarmSwitcher(),
            _HomeHero(
              name: ref.watch(authProvider).profile?.name ?? '',
              farmName: farm?.name,
              onOpenDrawer: onOpenDrawer,
            ),
            if (farmId == null)
              const SizedBox.shrink()
            else ...[
              _QuickActions(onNavigate: onNavigate),
              _KpiGrid(
                waterSaved: ref.watch(waterSavedProvider),
                motorStatus: ref.watch(motorStatusProvider(farmId)),
                notifications: ref.watch(notificationsProvider),
                impact: ref.watch(impactProvider(farmId)),
              ),
              WeatherCard(provider: ref.watch(farmWeatherProvider(farmId))),
              _SignalCard(provider: ref.watch(motorStatusProvider(farmId))),
              _KpiMatrixCard(provider: ref.watch(impactProvider(farmId))),
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

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.name,
    required this.farmName,
    required this.onOpenDrawer,
  });

  final String name;
  final String? farmName;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF8D5A2B)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.eco, color: Colors.white),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'Menu',
                onPressed: onOpenDrawer,
                icon: const Icon(Icons.apps),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l10n.homeWelcome(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            farmName == null
                ? l10n.homeNoFarm
                : '$farmName · ${l10n.homeWeatherIntelligence}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <({String label, IconData icon, int index, Color color})>[
      (
        label: l10n.navMotor,
        icon: Icons.water_drop_outlined,
        index: 1,
        color: const Color(0xFF1976D2),
      ),
      (
        label: l10n.navMarket,
        icon: Icons.storefront_outlined,
        index: 2,
        color: const Color(0xFF8D5A2B),
      ),
      (
        label: l10n.navUpload,
        icon: Icons.camera_alt_outlined,
        index: 3,
        color: const Color(0xFF00897B),
      ),
      (
        label: l10n.navRecommendations,
        icon: Icons.insights_outlined,
        index: 4,
        color: const Color(0xFF6A1B9A),
      ),
      (
        label: l10n.navInventory,
        icon: Icons.inventory_2_outlined,
        index: 8,
        color: const Color(0xFF455A64),
      ),
      (
        label: l10n.navPerformance,
        icon: Icons.bar_chart_outlined,
        index: 9,
        color: const Color(0xFFC62828),
      ),
    ];

    return SizedBox(
      height: 98,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, i) {
          final item = actions[i];
          return _ActionButton(
            label: item.label,
            icon: item.icon,
            color: item.color,
            onTap: () => onNavigate(item.index),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: actions.length,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final impactMetrics = [
      ...?impact.value?.precisionAgriculture,
      ...?impact.value?.circularSupplyChain,
    ];
    double metric(String type) {
      for (final item in impactMetrics) {
        if (item.metricType == type) return item.value ?? 0;
      }
      return 0;
    }

    final foodRescued = metric('food_rescued_kg');
    final co2eAvoided = metric('co2e_avoided_kg');

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
            label: 'Food rescued',
            value: '${foodRescued.toStringAsFixed(1)} kg',
            color: const Color(0xFF6A1B9A),
          ),
          _KpiTile(
            icon: Icons.agriculture_outlined,
            label: 'CO2e avoided',
            value: '${co2eAvoided.toStringAsFixed(1)} kg',
            color: const Color(0xFF795548),
          ),
        ],
      ),
    );
  }
}

class _KpiMatrixCard extends StatelessWidget {
  const _KpiMatrixCard({required this.provider});

  final AsyncValue<ImpactMetrics> provider;

  @override
  Widget build(BuildContext context) {
    final matrix = provider.value?.kpiMatrix ?? const <KpiItem>[];
    if (matrix.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.functions_outlined),
        title: const Text('KPI calculation matrix'),
        children: [
          for (final item in matrix)
            ListTile(
              title: Text(item.label),
              subtitle: Text(
                [
                  if (item.formula != null) item.formula!,
                  if (item.parameters.isNotEmpty)
                    'Parameters: ${item.parameters.join(', ')}',
                ].join('\n'),
              ),
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
    final status = result?.data;
    final gateway = status?.loraGateway;
    final signal = gateway?.lastAckRssi ?? status?.signalStrength;
    final relay = status?.motorRelayState;
    final isRunning = status?.currentStatus != null;
    final deviceUid =
        gateway?.deviceUid ?? status?.device?['device_uid']?.toString();
    final lastCommand = gateway?.lastCommand;
    final lastAck = gateway?.lastAck;
    final commandParts = [
      if (lastCommand != null && lastCommand.isNotEmpty) 'Last: $lastCommand',
      if (lastAck != null && lastAck.isNotEmpty && lastAck != 'none')
        'ACK received',
      if (lastAck == 'none') 'No ACK yet',
    ];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result?.fromCache ?? false)
            StaleBanner(savedAt: result!.savedAt!),
          ListTile(
            leading: Icon(
              gateway?.reachable == true ? Icons.sensors : Icons.sensors_off,
            ),
            title: Text('LoRa gateway'),
            subtitle: Text(
              gateway?.reachable == true
                  ? [
                      if (deviceUid != null && deviceUid.isNotEmpty) deviceUid,
                      if (gateway?.ip != null && gateway!.ip!.isNotEmpty)
                        gateway.ip!,
                    ].join(' · ')
                  : l10n.homeNoSignal,
              style: TextStyle(
                color: gateway?.reachable == true ? Colors.green : Colors.grey,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.network_check),
            title: Text(l10n.homeSignalStrength),
            subtitle: Text(
              signal == null
                  ? l10n.homeNoSignal
                  : '${signal < 0 ? signal : -signal} dBm'
                        '${gateway?.lastAckSnr == null ? '' : ' · SNR ${gateway!.lastAckSnr!.toStringAsFixed(1)}'}',
              style: TextStyle(
                color: signal == null ? Colors.grey : _signalColor(signal),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_input_antenna),
            title: const Text('LoRa command'),
            subtitle: Text(
              commandParts.isEmpty
                  ? l10n.homeNoSignal
                  : commandParts.join(' · '),
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
