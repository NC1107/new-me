import 'package:flutter_test/flutter_test.dart';
import 'package:newme/util/client_op_id.dart';
import 'package:newme/util/format.dart';
import 'package:newme/util/people.dart';

void main() {
  test('one date format: Oct 28, Wed, Oct 28 and Wednesday, Oct 28', () {
    expect(dayShort('2026-10-28'), 'Oct 28');
    expect(dayWithWeekday('2026-10-28'), 'Wed, Oct 28');
    expect(dayLong('2026-10-28'), 'Wednesday, Oct 28');
  });

  test('meFirst moves the signed-in person to the front and keeps the rest in order', () {
    expect(meFirst([1, 2, 3], 2, (i) => i), [2, 1, 3]);
    expect(meFirst([1, 2], null, (i) => i), [1, 2]);
    expect(meFirst([1, 2], 9, (i) => i), [1, 2]);
  });

  test('a typed pairing code is upper-cased and grouped in fours, capped at 16 symbols', () {
    const formatter = InviteCodeFormatter();
    String typed(String raw) =>
        formatter.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: raw)).text;

    expect(typed('b3nb'), 'B3NB');
    expect(typed('b3nb5'), 'B3NB-5');
    expect(typed(' b3nb-51b6 hmy6-77rj '), 'B3NB-51B6-HMY6-77RJ');
    expect(typed('B3NB51B6HMY677RJEXTRA'), 'B3NB-51B6-HMY6-77RJ');
    expect(typed(''), '');
  });

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
