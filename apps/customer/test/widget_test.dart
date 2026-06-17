import 'package:flutter_test/flutter_test.dart';

import 'package:ubike_customer/models/models.dart';

void main() {
  test('service catalogue matches the U-Bike spec minimum fares', () {
    final byId = {for (final c in ServiceCategory.all) c.id: c};
    expect(byId['standard_bike']!.minFare, 120);
    expect(byId['electric_bike']!.minFare, 150);
    expect(byId['economy']!.minFare, 300);
    expect(byId['comfort']!.minFare, 450);
    expect(byId['suv']!.minFare, 600);
    expect(byId['errands']!.minFare, 300);
  });

  test('FareQuote parses backend response', () {
    final q = FareQuote.fromJson({'fare': 360, 'upfront': 180, 'balance': 180});
    expect(q.fare, 360);
    expect(q.upfront, 180);
    expect(q.balance, 180);
  });
}
