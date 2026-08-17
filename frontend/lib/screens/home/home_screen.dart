import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/backend.dart';
import '../../widgets/shared.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final farms = ref.watch(farmsProvider);
    final farm = farms.currentFarm;
    final farmId = farm?.id;

    // In-app alert when a new notification row lands (realtime).
    ref.listen(realtimeController, (prev, next) {
      if (next > (prev ?? 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.homeNotifications)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
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
            if (farmId == null) const SizedBox.shrink() else ...[
              _WaterSavedCard(
                provider: ref.watch(waterSavedProvider),
              ),
              _SignalCard(
                provider: ref.watch(motorStatusProvider(farmId)),
              ),
            ],
            _NotificationsPreview(
              provider: ref.watch(notificationsProvider),
            ),
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
      ref.read(farmsProvider.notifier).load();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

class _WaterSavedCard extends ConsumerWidget {
  const _WaterSavedCard({required this.provider});

  final AsyncValue<WaterSaved> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = provider.value?.totalLiters ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeWaterSaved,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '${value.toStringAsFixed(1)} ${l10n.homeLiters}',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: const Color(0xFF2E7D32)),
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
    final signal = provider.value?.data.signalStrength;
    return Card(
      child: ListTile(
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
                Text(l10n.homeNotifications,
                    style: Theme.of(context).textTheme.titleMedium),
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