import 'package:flutter_test/flutter_test.dart';
import 'package:newme/util/client_op_id.dart';
import 'package:newme/util/format.dart';

void main() {
  test('numbers get thousands separators and no stray decimals', () {
    expect(1850.formatted, '1,850');
    expect(0.formatted, '0');
    expect(1234567.formatted, '1,234,567');
    expect(82.5.formatted, '82.5');
    expect(82.0.formatted, '82');
  });

  test('relative time rounds down and never goes negative', () {
    final now = DateTime.utc(2026, 10, 26, 14);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(relativeTime(now.add(const Duration(minutes: 5)), now), 'just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5, seconds: 59)), now), '5m ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3, minutes: 40)), now), '3h ago');
    expect(relativeTime(now.subtract(const Duration(hours: 49)), now), '2d ago');
  });

  test('date helpers step back across month and year edges', () {
    expect(previousDate('2026-10-26'), '2026-10-25');
    expect(previousDate('2026-11-01'), '2026-10-31');
    expect(previousDate('2027-01-01'), '2026-12-31');
    expect(weekdayShort('2026-10-27'), 'Tue');
  });

  test('a client op id is a version 4 UUID and never repeats', () {
    final id = newClientOpId();
    expect(
      id,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(newClientOpId(), isNot(id));
  });
}
