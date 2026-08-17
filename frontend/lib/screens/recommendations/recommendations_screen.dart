import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final farmId = ref.watch(farmsProvider).currentFarm?.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navRecommendations)),
      body: farmId == null
          ? Center(child: Text(l10n.homeNoFarm))
          : ref.watch(recommendationsProvider(farmId)).when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                onRetry: () =>
                    ref.refresh(recommendationsProvider(farmId)),
              ),
              data: (result) => ListView(
                children: [
                  const FarmSwitcher(),
                  if (result.fromCache) StaleBanner(savedAt: result.savedAt!),
                  const SizedBox(height: 8),
                  _AgentCard(
                    title: l10n.recommendationsHealth,
                    icon: Icons.health_and_safety_outlined,
                    agent: result.data.healthAnalysis,
                  ),
                  _AgentCard(
                    title: l10n.recommendationsYield,
                    icon: Icons.eco_outlined,
                    agent: result.data.yieldAnalysis,
                  ),
                  _NextSeasonCard(agent: result.data.nextSeason),
                  if (result.data.yieldForecasts.length > 1)
                    _YieldForecastChart(forecasts: result.data.yieldForecasts),
                ],
              ),
            ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.title,
    required this.icon,
    required this.agent,
  });

  final String title;
  final IconData icon;
  final AgentResult? agent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(_summary(agent) ?? '—'),
      ),
    );
  }

  String? _summary(AgentResult? agent) {
    if (agent == null) return null;
    final r = agent.resultJson;
    if (r is Map && r.isNotEmpty) {
      final parts = <String>[];
      if (r['health_status'] != null) parts.add(r['health_status'].toString());
      if (r['expected_yield_kg'] != null) parts.add('${r['expected_yield_kg']} kg');
      if (r['confidence'] != null) parts.add('${(r['confidence'] * 100).round()}%');
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    return 'No data yet.';
  }
}

class _NextSeasonCard extends StatelessWidget {
  const _NextSeasonCard({required this.agent});

  final AgentResult? agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crops = agent?.resultJson?['recommended_crops'] as List? ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.recommendationsNextSeason,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (crops.isEmpty)
              Text(l10n.recommendationsNoData)
            else
              for (final crop in crops)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.spa_outlined),
                  title: Text(crop['crop']?.toString() ?? crop.toString()),
                  subtitle: Text(crop['reason']?.toString() ?? ''),
                  trailing: crop['confidence'] != null
                      ? Text('${(crop['confidence'] * 100).round()}%')
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _YieldForecastChart extends StatelessWidget {
  const _YieldForecastChart({required this.forecasts});

  final List<YieldForecast> forecasts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reversed = forecasts.reversed.toList();
    final values =
        reversed.map((f) => f.expectedYieldKg ?? 0).toList(growable: false);
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.recommendationsForecasts,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _BarPainter(values, maxV),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.maxV);

  final List<double> values;
  final double maxV;

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / values.length * 0.6;
    final paint = Paint()..color = const Color(0xFF2E7D32);
    final gap = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / maxV) * (size.height - 10);
      final left = i * gap + (gap - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barW, h),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values || old.maxV != maxV;
}