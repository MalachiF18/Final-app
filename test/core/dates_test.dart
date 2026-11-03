import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/core/dates.dart';

void main() {
  // Fixed "now" with a time of day, so tests prove the time is ignored.
  final now = DateTime(2026, 11, 3, 15, 30);

  test('same day is due today', () {
    expect(relativeDue(DateTime(2026, 11, 3), now), 'Due today');
  });

  test('next day is due tomorrow', () {
    expect(relativeDue(DateTime(2026, 11, 4), now), 'Due tomorrow');
  });

  test('three days out', () {
    expect(relativeDue(DateTime(2026, 11, 6), now), 'Due in 3 days');
  });

  test('one day overdue', () {
    expect(relativeDue(DateTime(2026, 11, 2), now), 'Overdue by 1 day');
  });

  test('five days overdue', () {
    expect(relativeDue(DateTime(2026, 10, 29), now), 'Overdue by 5 days');
  });

  test('same date with different times is due today', () {
    expect(relativeDue(DateTime(2026, 11, 3, 23, 59), now), 'Due today');
    expect(relativeDue(DateTime(2026, 11, 3, 0, 1), now), 'Due today');
  });

  test('counts days across a month boundary', () {
    final endOfMonth = DateTime(2026, 10, 30, 22);
    expect(relativeDue(DateTime(2026, 11, 2), endOfMonth), 'Due in 3 days');
    expect(
      relativeDue(DateTime(2026, 10, 30), DateTime(2026, 11, 2)),
      'Overdue by 3 days',
    );
  });
}
