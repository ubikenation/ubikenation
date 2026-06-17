import 'package:flutter_test/flutter_test.dart';

import 'package:ubike_rider_bike/models/models.dart';

void main() {
  test('all 10 approved adjustment reasons are present', () {
    expect(AdjustmentReasons.all.length, 10);
    final values = AdjustmentReasons.all.map((r) => r.value).toSet();
    expect(values.contains('heavy_rain'), isTrue);
    expect(values.contains('road_closure'), isTrue);
    expect(values.contains('public_event_congestion'), isTrue);
  });

  test('FeeQuote infers payment requirement from fee', () {
    final free = FeeQuote.fromJson({'isFounding': true, 'registrationFee': 0, 'slotsRemaining': 5});
    expect(free.paymentRequired, isFalse);
    final paid = FeeQuote.fromJson({'isFounding': false, 'registrationFee': 2000, 'slotsRemaining': 0});
    expect(paid.paymentRequired, isTrue);
  });
}
