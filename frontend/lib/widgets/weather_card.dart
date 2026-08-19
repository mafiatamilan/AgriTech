import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';

/// Compact weather card for the Home screen. Shows live weather from the
/// existing backend weather service plus a short irrigation insight derived
/// from the latest irrigation decision. Degrades gracefully when weather is
/// unavailable (all-null `WeatherInfo` or an error value).
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key, required this.provider});

  final AsyncValue<WeatherInfo> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final weather = provider.value;
    final temp = weather?.avgTempC;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(l10n.homeWeatherTitle,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (temp == null)
              Text(
                l10n.homeWeatherUnavailable,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              Text(
                '${temp.round()}°C · ${weather?.condition ?? l10n.homeWeatherConditionUnknown}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _WeatherLine(
                icon: Icons.water_drop_outlined,
                text: l10n.homeWeatherHumidity(
                    (weather?.humidityPct ?? 0).round()),
              ),
              _WeatherLine(
                icon: Icons.beach_access_outlined,
                text: l10n.homeWeatherRain(
                    (weather?.rainfallMmToday ?? 0).toStringAsFixed(1)),
              ),
              _WeatherLine(
                icon: Icons.air,
                text: l10n.homeWeatherWind(
                    (weather?.windSpeedKmph ?? 0).toStringAsFixed(0)),
              ),
              if (weather?.maxTempC != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${l10n.homeWeatherMax} ${weather!.maxTempC!.round()}°C',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (weather?.irrigation != null)
                IrrigationInsight(l10n: l10n, decision: weather!.irrigation!),
            ],
            const Divider(height: 16),
            Row(
              children: [
                const Icon(Icons.psychology_outlined, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.homeWeatherIntelligence,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.blueGrey),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class IrrigationInsight extends StatelessWidget {
  const IrrigationInsight({super.key, required this.l10n, required this.decision});

  final AppLocalizations l10n;
  final IrrigationDecision decision;

  @override
  Widget build(BuildContext context) {
    final duration = decision.recommendedDurationMinutes;
    final volume = decision.estimatedWaterVolumeLiters;
    final flow = decision.pumpFlowLpm;
    final emoji = decision.estimatedWaterNeedMm != null &&
            (decision.estimatedWaterNeedMm! < 3)
        ? '🌧️'
        : '☀️';
    final String text;
    if (duration != null && volume != null && flow != null) {
      text = l10n.homeIrrigationRecommendation(duration, volume.round(), flow);
    } else if (decision.estimatedWaterNeedMm != null &&
        decision.estimatedWaterNeedMm! < 3) {
      text = l10n.homeWeatherRainExpected;
    } else {
      text = l10n.homeWeatherHotDry;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _WeatherLine extends StatelessWidget {
  const _WeatherLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}