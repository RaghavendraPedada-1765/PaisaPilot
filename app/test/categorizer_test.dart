import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/import/categorizer.dart';

/// Output of tools/categorize.py on the real statement. Lives in the
/// git-ignored data/ folder, so this check only runs on Raghav's machine.
final _pythonOutput = File('../data/transactions_categorised.csv');

/// Minimal CSV reader (quoted fields, doubled quotes), enough for that file.
List<List<String>> _readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) rows.add(row..add(field.toString()));
  return rows;
}

void main() {
  test('UPI description splits into payee and VPA', () {
    expect(party('UPI/DR/333333333333/ZUDIO/HDFC/zudio@hdfc/UPI//x'), ('ZUDIO', 'zudio@hdfc'));
    expect(party('SBINT FOR THE PERIOD'), ('SBINT FOR THE PERIOD', ''));
  });

  test('rules respect direction and fall back to unsorted', () {
    expect(categorise('SWIGGY', 'swiggy@yes', 'DR'), 'Food and cafes');
    expect(categorise('SWIGGY', 'swiggy@yes', 'CR'), isNull);
    expect(categorise('MAKEMYTRIP I', '', 'CR'), 'Trip bookings');
    expect(categorise('SOMEONE NEW', 'x@ybl', 'DR'), isNull);
  });

  test('matches tools/categorize.py on the real statement',
      skip: _pythonOutput.existsSync() ? false : 'data/ not present', () {
    final rows = _readCsv(_pythonOutput.readAsStringSync());
    final h = rows.first;
    final (dir, payee, vpa, cat, desc) = (h.indexOf('dir'), h.indexOf('payee'), h.indexOf('vpa'),
        h.indexOf('category'), h.indexOf('desc'));
    final data = rows.skip(1).where((r) => r.length == h.length).toList();
    expect(data, hasLength(467));
    var diffs = 0;
    for (final r in data) {
      final (name, v) = party(r[desc]);
      final got = categorise(name, v, r[dir]) ?? 'Unsorted';
      if (name != r[payee] || v != r[vpa] || got != r[cat]) diffs++;
    }
    expect(diffs, 0);
  });
}
