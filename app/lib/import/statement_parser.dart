/// Canara e-passbook parser (port of tools/parse_statement.py).
///
/// Input is the statement as layout text (what `pdftotext -layout` produces).
/// Printed balances drop the minus sign, so a signed running balance is
/// tracked and every row is checked against it.
library;

class StatementRow {
  const StatementRow({
    required this.date,
    required this.desc,
    required this.amount,
    required this.direction,
    required this.balance,
    required this.ok,
  });

  final String date; // ISO date
  final String desc;
  final double amount;
  final String direction; // CR or DR
  final double balance; // signed running balance
  final bool ok; // matches the printed balance

  static final _time = RegExp(r'(\d{2}:\d{2}:\d{2})$');

  /// UPI reference (`UPI/DR/<ref>/...`), shared with the SMS alert.
  String? get upiRef {
    final p = desc.split('/');
    return p.length > 2 && p[0] == 'UPI' ? p[2].trim() : null;
  }

  String? get time => _time.firstMatch(desc)?.group(1);
}

class StatementResult {
  const StatementResult(this.opening, this.rows, this.bad);
  final double? opening;
  final List<StatementRow> rows;
  final List<List<String>> bad; // blocks that could not be parsed

  int get mismatches => rows.where((r) => !r.ok).length;
  double? get closing => rows.isEmpty ? null : rows.last.balance;
}

final _dateRe = RegExp(r'^\s*(\d{2}-\d{2}-\d{4})\s');
final _amtRe = RegExp(r'(?<![\w/.])(\d[\d,]*\.\d{2})(?![\w/])');
final _skipRe = RegExp(
    r'^\s*(Date\s+Particulars|page \d+|Statement for|Customer Id|Name\s|Phone\s|Address\s)',
    caseSensitive: false);

double _num(String s) => double.parse(s.replaceAll(',', ''));
double _round2(double x) => (x * 100).round() / 100;

final _openingRe = RegExp(r'Opening\s+Balance');
final _closingRe = RegExp(r'Closing\s+Balance');
final _chqRe = RegExp(r'^\s*Chq\s*:');

StatementResult parseStatement(String text) {
  double? opening;
  var awaitingOpening = false; // label seen, amount on a following line
  final blocks = <List<String>>[];
  var block = <String>[];
  for (final ln in text.split(RegExp(r'\r?\n'))) {
    if (_openingRe.hasMatch(ln) || awaitingOpening) {
      final amounts = _amtRe.allMatches(ln).toList();
      awaitingOpening = amounts.isEmpty && !_dateRe.hasMatch(ln);
      if (amounts.isNotEmpty) opening = _num(amounts.last.group(1)!);
      block = [];
      continue;
    }
    if (opening == null) continue;
    if (ln.contains('END OF STATEMENT') || ln.trim() == 'DISCLAIMER') break;
    if (_closingRe.hasMatch(ln)) continue;
    if (_skipRe.hasMatch(ln) || ln.trim().isEmpty) continue;
    if (_chqRe.hasMatch(ln)) {
      if (block.isNotEmpty) blocks.add(block);
      block = [];
      continue;
    }
    block.add(ln);
  }
  if (block.isNotEmpty) blocks.add(block);

  final rows = <StatementRow>[];
  final bad = <List<String>>[];
  var prev = opening ?? 0;
  for (final b in blocks) {
    String? date;
    var amts = <double>[];
    final parts = <String>[];
    for (final ln in b) {
      final m = _dateRe.firstMatch(ln);
      var left = ln;
      if (m != null) {
        date = m.group(1);
        // amounts live in the right-hand columns
        final cols = _amtRe.allMatches(ln).where((a) => a.start >= 40).toList();
        if (cols.isNotEmpty) {
          amts = [for (final a in cols) _num(a.group(1)!)];
          left = ln.substring(m.end, cols.first.start);
        } else {
          left = ln.substring(m.end);
        }
      }
      parts.add(left.trim());
    }
    final desc = parts.where((p) => p.isNotEmpty).join();
    if (date == null || amts.length < 2) {
      bad.add(b);
      continue;
    }
    final amount = amts[amts.length - 2];
    final printed = amts.last;
    final String direction;
    if (desc.contains('/CR/') || desc.startsWith('INET-IMPS-CR')) {
      direction = 'CR';
    } else if (desc.contains('/DR/')) {
      direction = 'DR';
    } else {
      direction = ((prev + amount).abs() - printed).abs() < 0.01 ? 'CR' : 'DR';
    }
    prev = _round2(direction == 'CR' ? prev + amount : prev - amount);
    final d = date.split('-');
    rows.add(StatementRow(
      date: '${d[2]}-${d[1]}-${d[0]}',
      desc: desc,
      amount: amount,
      direction: direction,
      balance: prev,
      ok: (prev.abs() - printed).abs() < 0.01,
    ));
  }
  return StatementResult(opening, rows, bad);
}
