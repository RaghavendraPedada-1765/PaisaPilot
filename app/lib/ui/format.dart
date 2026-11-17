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

/// ISO date → `Today`, `Yesterday` or `14 Nov 2026`.
String dayLabel(String isoDate, [DateTime? now]) {
  final d = DateTime.parse(isoDate);
  final today = now ?? DateTime.now();
  final diff = DateTime(today.year, today.month, today.day).difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}
