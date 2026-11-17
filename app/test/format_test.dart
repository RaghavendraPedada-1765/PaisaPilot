import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/ui/format.dart';

void main() {
  test('rupees use Indian grouping and drop zero paise', () {
    expect(inr(0), '₹0');
    expect(inr(300), '₹300');
    expect(inr(6516), '₹6,516');
    expect(inr(123456.5), '₹1,23,456.50');
    expect(inr(10000000), '₹1,00,00,000');
    expect(inr(-149.12), '-₹149.12');
    expect(inr(0.999), '₹1');
  });

  test('months', () {
    expect(monthLabel('2026-11'), 'November 2026');
    expect(shiftMonth('2026-01', -1), '2025-12');
    expect(shiftMonth('2026-12', 1), '2027-01');
  });

  test('times in 12-hour form', () {
    expect(timeLabel('19:05:00'), '7:05 PM');
    expect(timeLabel('00:15:00'), '12:15 AM');
    expect(timeLabel('12:00:30'), '12:00 PM');
    expect(timeLabel('09:30'), '9:30 AM');
    expect(timeLabel(null), isNull);
  });

  test('day labels', () {
    final now = DateTime(2026, 11, 16, 20);
    expect(dayLabel('2026-11-16', now), 'Today');
    expect(dayLabel('2026-11-15', now), 'Yesterday');
    expect(dayLabel('2026-10-22', now), '22 Oct 2026');
  });
}
