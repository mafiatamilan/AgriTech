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
}
