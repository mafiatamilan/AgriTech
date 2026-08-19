import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

/// Tracks & Impact dashboard.
///
/// Shows the farm's quantified impact grouped into the two hackathon tracks:
/// Precision Agriculture (water saved, yield gain, fertilizer reduction) and
/// Circular Supply Chain (food rescued, CO2e avoided, economic value
/// recovered). All numbers come from stored `impact_metrics` rows written by
/// the backend impact layer — never fabricated client-side.
class ImpactScreen extends ConsumerWidget {
  const ImpactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final farm = ref.watch(farmsProvider).currentFarm;
    if (farm == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navImpact)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.impactSelectFarm, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final impact = ref.watch(impactProvider(farm.id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navImpact)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(impactProvider(farm.id)),
        child: impact.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            onRetry: () => ref.invalidate(impactProvider(farm.id)),
          ),
          data: (data) {
            if (data.isEmpty) {
              return ListView(
                children: [
                  const FarmSwitcher(),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.impactEmpty)),
                  ),
                ],
              );
            }
            return ListView(
              children: [
                const FarmSwitcher(),
                if (data.precisionAgriculture.isNotEmpty)
                  _TrackSection(
                    title: l10n.impactPrecisionAgriculture,
                    icon: Icons.grass,
                    metrics: data.precisionAgriculture,
                  ),
                if (data.circularSupplyChain.isNotEmpty)
                  _TrackSection(
                    title: l10n.impactCircularSupplyChain,
                    icon: Icons.recycling,
                    metrics: data.circularSupplyChain,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackSection extends StatelessWidget {
  const _TrackSection({
    required this.title,
    required this.icon,
    required this.metrics,
  });

  final String title;
  final IconData icon;
  final List<ImpactMetricDetails> metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        for (final m in metrics) _MetricCard(metric: m),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final ImpactMetricDetails metric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = metric.value;
    final unit = metric.unit ?? '';
    final baseline = metric.baselineValue;
    final optimized = metric.optimizedValue;
    final basis = metric.measuredOrEstimated == 'measured'
        ? l10n.impactMeasured
        : l10n.impactEstimated;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          metric.metricType.contains('water')
              ? Icons.water_drop
              : Icons.eco,
          color: const Color(0xFF2E7D32),
        ),
        title: Text(metric.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (baseline != null || optimized != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l10n.impactBaseline}: ${_fmt(baseline, unit)} · '
                  '${l10n.impactOptimized}: ${_fmt(optimized, unit)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (metric.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${fmtDate(metric.createdAt)} · $basis',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        trailing: Text(
          _fmt(value, unit),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  String _fmt(double? v, String unit) {
    if (v == null) return '—';
    final n = v.toStringAsFixed(1);
    return unit.isEmpty ? n : '$n $unit';
  }
}