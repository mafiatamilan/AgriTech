import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agritech/l10n/app_localizations.dart';
import 'package:agritech/models/models.dart';
import 'package:agritech/widgets/weather_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('weather card renders temperature and insight', (tester) async {
    final weather = WeatherInfo(
      avgTempC: 28,
      maxTempC: 34,
      humidityPct: 72,
      rainfallMmToday: 2.4,
      windSpeedKmph: 11,
      condition: 'partly_cloudy',
      source: 'open_meteo',
      irrigation: IrrigationDecision(
        decision: 'water_now',
        recommendedDurationMinutes: 18,
        estimatedWaterNeedMm: 4.1,
        estimatedWaterVolumeLiters: 2060,
        fieldAreaM2: 500,
        pumpFlowLpm: 12,
        pumpFlowEstimated: false,
        reasoning: 'needs water',
        reasonLabels: ['needs water'],
      ),
    );
    await tester.pumpWidget(_wrap(ProviderScope(
      child: WeatherCard(provider: AsyncValue.data(weather)),
    )));

    expect(find.textContaining('28°C'), findsOneWidget);
    expect(find.textContaining('Humidity'), findsOneWidget);
    expect(find.textContaining('2.4 mm'), findsOneWidget);
    expect(find.textContaining('11 km/h'), findsOneWidget);
    expect(find.textContaining('18'), findsWidgets);
    expect(find.textContaining('2060'), findsWidgets);
  });

  testWidgets('weather failure shows unavailable without crashing', (tester) async {
    final empty = WeatherInfo();
    await tester.pumpWidget(_wrap(ProviderScope(
      child: WeatherCard(provider: AsyncValue.data(empty)),
    )));
    expect(find.textContaining('unavailable'), findsOneWidget);
  });
}
