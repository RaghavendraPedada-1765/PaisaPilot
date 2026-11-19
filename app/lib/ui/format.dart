/// Rupee amounts with Indian digit grouping: ₹1,23,456.50, ₹300.
String inr(double value) {
  final paise = (value.abs() * 100).round();
  final digits = (paise ~/ 100).toString();
  final groups = <String>[];
  var rest = digits;
  if (rest.length > 3) {
    groups.insert(0, rest.substring(rest.length - 3));
    rest = rest.substring(0, rest.length - 3);
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
  }
  groups.insert(0, rest);
  final fraction = paise % 100 == 0 ? '' : '.${(paise % 100).toString().padLeft(2, '0')}';
  return '${value < 0 ? '-' : ''}₹${groups.join(',')}$fraction';
}

/// Money with an explicit direction: `+₹500` received, `−₹500` paid (a true
/// minus sign, U+2212).
String signedInr(double amount, {required bool credit}) => '${credit ? '+' : '−'}${inr(amount.abs())}';

/// A net figure with its sign: `+₹84`, `−₹3,888.90`, `₹0`.
String signedNet(double value) => value == 0 ? '₹0' : signedInr(value, credit: value > 0);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// `2026-11` → `November 2026`.
String monthLabel(String month) {
  final [y, m] = month.split('-');
  return '${_monthNames[int.parse(m) - 1]} $y';
}

/// Shifts a `YYYY-MM` month by [delta] months.
String shiftMonth(String month, int delta) {
  final [y, m] = month.split('-').map(int.parse).toList();
  final d = DateTime(y, m + delta);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

String currentMonth([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

/// `HH:MM[:SS]` → `7:05 PM`; null when there is no time.
String? timeLabel(String? hms) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hms ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  return '${h % 12 == 0 ? 12 : h % 12}:${m.group(2)} ${h < 12 ? 'AM' : 'PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Day group heading: `Today`, `Yesterday`, `Sat 14 Nov`, or `Sat 14 Nov
/// 2025` outside the current year.
String dayHeading(String isoDate, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final relative = dayLabel(isoDate, today);
  if (relative == 'Today' || relative == 'Yesterday') return relative;
  final d = DateTime.parse(isoDate);
  final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1].substring(0, 3)}';
  return d.year == today.year ? base : '$base ${d.year}';
}

typedef Period = ({String from, String to});

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What Home compares a month with. The current month is still running, so
/// it is compared with the same days of the previous month (`vs 1–18 Oct`);
/// any other month is compared with the whole previous month.
({Period current, Period previous, String label, bool partial}) monthComparison(String month, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final [y, m] = month.split('-').map(int.parse).toList();
  final last = DateTime(y, m + 1, 0).day;
  final prev = DateTime(y, m - 1);
  final prevLast = DateTime(y, m, 0).day;
  final prevName = _monthNames[prev.month - 1];
  final running = month == currentMonth(today) && today.day < last;
  if (!running) {
    return (
      current: (from: _iso(DateTime(y, m)), to: _iso(DateTime(y, m, last))),
      previous: (from: _iso(prev), to: _iso(DateTime(prev.year, prev.month, prevLast))),
      label: 'vs $prevName (full month)',
      partial: false,
    );
  }
  final day = today.day < prevLast ? today.day : prevLast;
  return (
    current: (from: _iso(DateTime(y, m)), to: _iso(today)),
    previous: (from: _iso(prev), to: _iso(DateTime(prev.year, prev.month, day))),
    label: 'vs ${day == 1 ? '1' : '1–$day'} ${prevName.substring(0, 3)} (same days)',
    partial: true,
  );
}

/// ISO date → `Today`, `Yesterday` or `14 Nov 2026`.
String dayLabel(String isoDate, [DateTime? now]) {
  final d = DateTime.parse(isoDate);
  final today = now ?? DateTime.now();
  final diff = DateTime(today.year, today.month, today.day).difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}
