import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/import/pdf_text.dart';
import 'package:paisapilot/import/statement_parser.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdf;

import 'statement_fixture.dart';

/// Lays strings out as glyphs on a page: [width] per character (or per-char
/// widths from [widthOf]), 14pt line pitch, first line at the top.
List<PositionedChar> page(List<String> lines, {double width = 5, double Function(String)? widthOf}) {
  final out = <PositionedChar>[];
  for (var row = 0; row < lines.length; row++) {
    final top = 800.0 - row * 14, bottom = top - 10;
    var x = 20.0;
    for (final ch in lines[row].split('')) {
      final w = widthOf?.call(ch) ?? width;
      out.add(PositionedChar(ch, x, x + w, top, bottom));
      x += ch == ' ' ? width : w; // a space still advances the pen
    }
  }
  return out;
}

void main() {
  test('monospace layout round-trips through the statement parser', () {
    final text = layoutText([page(statementFixture.split('\n'))]);
    final direct = parseStatement(statementFixture), viaLayout = parseStatement(text);
    expect(viaLayout.rows.map((r) => (r.date, r.desc, r.amount, r.direction, r.balance)),
        direct.rows.map((r) => (r.date, r.desc, r.amount, r.direction, r.balance)));
    expect(viaLayout.mismatches, 0);
  });

  test('proportional glyphs keep words whole and columns apart', () {
    double w(String c) => switch (c) { 'i' || 'l' || '.' || '/' || ',' => 2, 'M' || 'W' => 8, _ => 5 };
    final text = layoutText([page(['01-10-2026  UPI/CR/111111111111/ALICE              500.00     1,500.00'], widthOf: w)]);
    expect(text, contains('UPI/CR/111111111111/ALICE'));
    expect(RegExp(r'ALICE\s{2,}500\.00\s{2,}1,500\.00').hasMatch(text), isTrue, reason: text);
  });

  test('a zero-width glyph stays inside its word', () {
    final chars = page(['Balance   1,234.56']);
    final dot = chars.indexWhere((c) => c.char == '.');
    chars[dot] = PositionedChar('.', chars[dot].left, chars[dot].left, 0, 0); // empty box
    expect(layoutText([chars]), contains('1,234.56'));
  });

  test('an amount split after its decimal point is joined again', () {
    // As PDFium reports it: "1,234." then a space, then "56" touching it.
    final chars = page(['Balance   1,234.56']);
    final dot = chars.indexWhere((c) => c.char == '.');
    chars.insert(dot + 1, PositionedChar(' ', chars[dot].right, chars[dot].right, 0, 0));
    final text = layoutText([chars]);
    expect(text, contains('1,234.56'));
    expect(layoutText([page(['Opening Balance   12.   34 apples'])]), contains('12.   34'),
        reason: 'only touching pieces join');
  });

  test('lines come out top to bottom and pages in order', () {
    final text = layoutText([page(['first', 'second']), page(['third'])]);
    expect(text.trim().split('\n').map((l) => l.trim()), ['first', 'second', 'third']);
  });

  test('account number in the header', () {
    expect(statementAccount('Statement for A/c XXXXXXXX4321 for the period'), 'XXXXXXXX4321');
    expect(statementAccount('Account Number : 110012344321'), '110012344321');
    expect(statementAccount('no number here'), isNull);
  });

  // The real e-passbook lives in the git-ignored data/ folder on Raghav's PC.
  // Set PP_STATEMENT_PASSWORD if the PDF is encrypted.
  final pdfs = Directory('../data').existsSync()
      ? Directory('../data').listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf')).toList()
      : <File>[];
  test('real statement PDF reconciles like the Python parser', skip: pdfs.isEmpty ? 'no PDF in data/' : false,
      () async {
    await pdf.pdfrxInitialize(tmpPath: Platform.environment['PP_PDFIUM_DIR'] ?? 'X:/caches/pdfrx');
    final doc = await pdf.PdfDocument.openFile(pdfs.first.path,
        passwordProvider: () => Platform.environment['PP_STATEMENT_PASSWORD']);
    final result = parseStatement(layoutText(await documentChars(doc)));
    await doc.dispose();
    expect(result.bad, isEmpty);
    expect(result.rows, hasLength(467));
    expect(result.mismatches, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
