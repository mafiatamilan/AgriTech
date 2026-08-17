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

  test('CropMatchResult parses matches', () {
    final result = CropMatchResult.fromJson({
      'demand_request_id': 'd1',
      'status': 'matched',
      'matches': [
        {
          'buyer_name': 'GreenCo',
          'offered_price': 55,
          'distance_km': 3.2,
          'match_score': 0.9,
        }
      ],
    });
    expect(result.matches.single.buyerName, 'GreenCo');
    expect(result.status, 'matched');
  });
}