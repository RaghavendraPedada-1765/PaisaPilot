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

  test('signed amounts use + and a true minus', () {
    expect(signedInr(1250, credit: false), '−₹1,250');
    expect(signedInr(84.5, credit: true), '+₹84.50');
    expect(signedNet(-3888.9), '−₹3,888.90');
    expect(signedNet(0), '₹0');
  });

  test('day headings name the weekday', () {
    final now = DateTime(2026, 11, 18);
    expect(dayHeading('2026-11-18', now), 'Today');
    expect(dayHeading('2026-11-14', now), 'Sat 14 Nov');
    expect(dayHeading('2025-12-31', now), 'Wed 31 Dec 2025');
  });

  test('a running month is compared with the same days of the last one', () {
    final c = monthComparison('2026-11', DateTime(2026, 11, 18, 9));
    expect((c.previous.from, c.previous.to, c.partial), ('2026-10-01', '2026-10-18', true));
    expect(c.label, 'vs 1–18 Oct (same days)');
    // 30 March: February has no day 30, so its whole month counts.
    final march = monthComparison('2026-03', DateTime(2026, 3, 30));
    expect((march.previous.from, march.previous.to), ('2026-02-01', '2026-02-28'));
  });

  test('a finished month is compared with the whole previous month', () {
    final c = monthComparison('2026-10', DateTime(2026, 11, 18));
    expect((c.current.from, c.current.to), ('2026-10-01', '2026-10-31'));
    expect((c.previous.from, c.previous.to, c.partial), ('2026-09-01', '2026-09-30', false));
    expect(c.label, 'vs September (full month)');
    // The last day of a month counts as finished.
    expect(monthComparison('2026-11', DateTime(2026, 11, 30)).partial, isFalse);
  });
}
