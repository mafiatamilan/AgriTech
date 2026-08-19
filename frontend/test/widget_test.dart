import 'package:flutter_test/flutter_test.dart';

import 'package:agritech/models/models.dart';

void main() {
  test('DemandRequest parses and defaults to open', () {
    final req = DemandRequest.fromJson({
      'id': 'abc',
      'crop_name': 'Tomato',
      'expected_price': 50,
      'shelf_life_expiry': '2026-08-20T10:00:00Z',
    });
    expect(req.cropName, 'Tomato');
    expect(req.status, 'open');
  });

  test('CropMatchResult parses matches without match_score', () {
    final result = CropMatchResult.fromJson({
      'demand_request_id': 'd1',
      'status': 'matched',
      'matches': [
        {
          'buyer_name': 'GreenCo',
          'offered_price': 55,
          'distance_km': 3.2,
          'shelf_life_compatible': true,
        }
      ],
    });
    expect(result.matches.single.buyerName, 'GreenCo');
    expect(result.matches.single.shelfLifeCompatible, true);
    expect(result.status, 'matched');
  });

  test('MotorStatus reads top-level signal strength and relay state', () {
    final status = MotorStatus.fromJson({
      'last_watered': {},
      'next_watering': null,
      'current_status': null,
      'moisture_readings': <dynamic>[],
      'signal_strength': -72,
      'motor_relay_state': true,
    });
    expect(status.signalStrength, -72);
    expect(status.motorRelayState, true);
    expect(status.moistureReadings, isEmpty);
  });

  test('MotorStatus tolerates null signal and relay (disconnected)', () {
    final status = MotorStatus.fromJson({
      'moisture_readings': <dynamic>[],
      'signal_strength': null,
      'motor_relay_state': null,
    });
    expect(status.signalStrength, isNull);
    expect(status.motorRelayState, isNull);
  });

  test('HealthResult parses the backend contract shape', () {
    final health = HealthResult.fromJson({
      'health_status': 'Disease detected',
      'crop': 'corn',
      'disease': 'northern leaf blight',
      'diseases_detected': ['northern leaf blight'],
      'confidence_level': 'high',
      'severity': 'needs attention',
      'recommendation': 'Remove infected leaves.',
      'remedies': <dynamic>[],
      'prevention': <dynamic>[],
      'retake_image': false,
    });
    expect(health.healthStatus, 'Disease detected');
    expect(health.crop, 'corn');
    expect(health.diseasesDetected, ['northern leaf blight']);
    expect(health.confidenceLevel, 'high');
    expect(health.retakeImage, false);
  });

  test('HealthResult retake flag drives retake action', () {
    final health = HealthResult.fromJson({
      'health_status': 'Image unclear — retake',
      'crop': 'unknown',
      'disease': 'uncertain',
      'diseases_detected': <dynamic>[],
      'retake_image': true,
    });
    expect(health.retakeImage, true);
  });

  test('YieldResult parses the backend contract shape', () {
    final yieldR = YieldResult.fromJson({
      'crop_type': 'corn',
      'expected_yield_kg': 420,
      'confidence_level': 'medium',
      'risk_factors': <dynamic>[],
    });
    expect(yieldR.cropType, 'corn');
    expect(yieldR.expectedYieldKg, 420);
    expect(yieldR.confidenceLevel, 'medium');
  });

  test('PairedDevice parses pairing response', () {
    final device = PairedDevice.fromJson({
      'id': 'dev1',
      'device_uid': 'ESP32-0001',
    });
    expect(device.id, 'dev1');
    expect(device.deviceUid, 'ESP32-0001');
  });

  test('ImpactMetrics parses grouped tracks with baseline/optimized', () {
    final metrics = ImpactMetrics.fromJson({
      'farm_id': 'f1',
      'groups': {
        'precision_agriculture': [
          {
            'metric_type': 'water_saved_liters',
            'value': 480.0,
            'unit': 'L',
            'baseline_value': 1200.0,
            'optimized_value': 720.0,
            'measured_or_estimated': 'estimated',
            'created_at': '2026-08-18T10:00:00Z',
          },
        ],
        'circular_supply_chain': [
          {
            'metric_type': 'food_rescued_kg',
            'value': 50.0,
            'unit': 'kg',
            'baseline_value': 0.0,
            'optimized_value': 50.0,
          },
          {
            'metric_type': 'co2e_avoided_kg',
            'value': 125.0,
            'unit': 'kg CO2e',
            'baseline_value': 0.0,
            'optimized_value': 125.0,
          },
        ],
      },
      'count': 3,
    });
    expect(metrics.precisionAgriculture.single.metricType, 'water_saved_liters');
    expect(metrics.precisionAgriculture.single.baselineValue, 1200.0);
    expect(metrics.precisionAgriculture.single.optimizedValue, 720.0);
    expect(metrics.circularSupplyChain, hasLength(2));
    expect(metrics.circularSupplyChain.last.label, 'co2e avoided kg');
    expect(metrics.isEmpty, isFalse);
  });

  test('ImpactMetrics empty groups report isEmpty', () {
    final metrics = ImpactMetrics.fromJson({
      'farm_id': 'f1',
      'groups': {'precision_agriculture': [], 'circular_supply_chain': []},
      'count': 0,
    });
    expect(metrics.isEmpty, isTrue);
  });

  test('FieldArea round-trips irrigation config', () {
    final field = FieldArea(
      id: 'f1',
      fieldName: 'North field',
      areaSize: 500,
      cropType: 'tomato',
      plantedDate: '2026-08-10',
      soilType: 'loamy',
      pumpFlowLpm: 12,
    );
    expect(field.toJson()['area_size'], 500);
    expect(field.toJson()['crop_type'], 'tomato');
    expect(field.toJson()['planted_date'], '2026-08-10');
    expect(field.toJson()['soil_type'], 'loamy');
    expect(field.toJson()['pump_flow_lpm'], 12);

    final parsed = FieldArea.fromJson({
      'id': 'f1',
      'area_size': 500,
      'crop_type': 'tomato',
      'planted_date': '2026-08-10',
      'soil_type': 'loamy',
      'pump_flow_lpm': 12,
    });
    expect(parsed.areaSize, 500);
    expect(parsed.cropType, 'tomato');
    expect(parsed.pumpFlowLpm, 12);
  });

  test('FieldArea tolerates missing optional config', () {
    final field = FieldArea.fromJson({'id': 'f1'});
    expect(field.areaSize, isNull);
    expect(field.pumpFlowLpm, isNull);
    expect(field.cropType, isNull);
  });

  test('WeatherInfo parses weather plus irrigation decision', () {
    final weather = WeatherInfo.fromJson({
      'avg_temp_c': 28.5,
      'max_temp_c': 33,
      'humidity_pct': 72,
      'rainfall_mm_today': 2.4,
      'wind_speed_kmph': 11,
      'condition': 'Partly Cloudy',
      'irrigation': {
        'decision': 'water_now',
        'recommended_duration_minutes': 18,
        'estimated_water_need_mm': 4.3,
        'estimated_water_volume_liters': 216.0,
        'field_area_m2': 500,
        'pump_flow_lpm': 12,
        'pump_flow_estimated': false,
        'reasoning': 'Soil dries faster',
        'reason_labels': ['Using configured pump flow 12 L/min'],
      },
    });
    expect(weather.avgTempC, 28.5);
    expect(weather.humidityPct, 72);
    expect(weather.isRainExpected, isTrue);
    final d = weather.irrigation!;
    expect(d.recommendedDurationMinutes, 18);
    expect(d.estimatedWaterVolumeLiters, 216.0);
    expect(d.pumpFlowLpm, 12);
    expect(d.pumpFlowEstimated, isFalse);
  });

  test('WeatherInfo without irrigation does not crash', () {
    final weather = WeatherInfo.fromJson({'avg_temp_c': 30, 'condition': 'Sunny'});
    expect(weather.irrigation, isNull);
    expect(weather.isRainExpected, isFalse);
  });

  test('IrrigationDecision marks estimated pump flow fallback', () {
    final d = IrrigationDecision.fromJson({
      'decision': 'monitor',
      'recommended_duration_minutes': 12,
      'pump_flow_estimated': true,
      'reason_labels': ['Using fallback pump estimate (0.35 mm/min)'],
    });
    expect(d.pumpFlowEstimated, isTrue);
    expect(d.reasonLabels.single, contains('fallback'));
  });

  test('InventoryItem parses field_id and storage/quality', () {
    final item = InventoryItem.fromJson({
      'id': 'inv-1',
      'farm_id': 'farm-1',
      'crop_name': 'tomato',
      'quantity': 20,
      'harvested_date': '2026-08-10',
      'storage_type': 'refrigerated',
      'quality_grade': 'B',
      'field_id': 'field-9',
      'status_info': {'id': 's1', 'inventory_id': 'inv-1', 'status': 'fresh', 'remaining_days': 5},
    });
    expect(item.fieldId, 'field-9');
    expect(item.storageType, 'refrigerated');
    expect(item.qualityGrade, 'B');
    expect(item.statusInfo!.status, 'fresh');
  });
}
