import 'package:flutter_test/flutter_test.dart';
import 'package:newme/util/units.dart';

void main() {
  test('weights, loads and heights read in each system', () {
    expect(Units.metric.weight(82.44), '82.4 kg');
    expect(Units.imperial.weight(82.44), '181.7 lb');
    expect(Units.imperial.load(22.68), '50 lb');
    expect(Units.imperial.height(178), '5 ft 10 in');
    expect(Units.metric.height(178), '178 cm');
    expect(cmFromFeetInches(5, 10), 177.8);
  });

  test('paces read exactly in each system', () {
    expect(Units.metric.pace(0.25), '0.25 kg a week');
    expect(Units.metric.pace(0.5), '0.5 kg a week');
    expect(
      [for (final p in Units.imperial.losePaces) Units.imperial.pace(p)],
      ['0.5 lb a week', '1 lb a week'],
    );
    expect(
      [for (final p in Units.imperial.gainPaces) Units.imperial.pace(p)],
      ['0.25 lb a week', '0.5 lb a week', '1 lb a week'],
    );
  });

  test('the region picks the default', () {
    expect(unitsForRegion('US'), Units.imperial);
    expect(unitsForRegion('gb'), Units.metric);
    expect(unitsForRegion(null), Units.metric);
  });
}
