import 'package:pdfrx/pdfrx.dart';

/// One character on a PDF page, in PDF coordinates (y grows upward).
class PositionedChar {
  const PositionedChar(this.char, this.left, this.right, this.top, this.bottom);
  final String char;
  final double left, right, top, bottom;
  double get height => top - bottom;
  double get middle => (top + bottom) / 2;
}

/// A word: characters that are contiguous in the PDF's own text order.
class _Word {
  _Word(this.first);
  final PositionedChar first;
  final text = StringBuffer();
  late double right = first.right;
  double get left => first.left;
}

/// A run of words that the PDF's text order keeps on one line.
class _Run {
  final words = <_Word>[];
  final letters = <PositionedChar>[];

  // Typical letter, so a high-set `*` or a low `,` does not move the run.
  PositionedChar get _typical {
    final pool = letters.isEmpty ? [for (final w in words) w.first] : letters;
    final sorted = [...pool]..sort((a, b) => a.middle.compareTo(b.middle));
    return sorted[sorted.length ~/ 2];
  }

  double get middle => _typical.middle;
  double get height => _typical.height;
}

final _alnum = RegExp(r'[A-Za-z0-9]');
final _numberHead = RegExp(r'\d[.,]$');
final _digitStart = RegExp(r'^\d');

/// PDFium's text puts a space inside some amounts (`1,234. 56`): the
/// decimals are drawn as a separate piece. Rejoin a word ending in a digit
/// and `.` or `,` with a digit word right after it.
List<_Word> _joinNumbers(List<_Word> words, double cell) {
  final out = <_Word>[];
  for (final w in words) {
    final last = out.isEmpty ? null : out.last;
    final text = w.text.toString();
    if (last != null &&
        _numberHead.hasMatch(last.text.toString()) &&
        _digitStart.hasMatch(text) &&
        w.left - last.right < cell * 1.5) {
      last.text.write(text);
      if (w.right > last.right) last.right = w.right;
    } else {
      out.add(w);
    }
  }
  return out;
}

/// Rebuilds `pdftotext -layout`-style text from a PDF's characters, so
/// [parseStatement] can read statements on the phone.
///
/// [pages] hold each page's characters in the PDF's text order, whitespace
/// and line breaks included. Words come from that order (glyph boxes hug the
/// ink, so gaps inside a word vary too much to tell words apart). Runs at the
/// same height form a row, and each word's left edge sets its column, which
/// keeps table columns apart.
String layoutText(List<List<PositionedChar>> pages) {
  final out = StringBuffer();
  for (final chars in pages) {
    final runs = <_Run>[];
    var run = _Run();
    _Word? word;
    PositionedChar? prev;
    for (final c in chars) {
      final ink = c.char.trim().isNotEmpty;
      // PDFium gives some glyphs, such as '.', an empty box (often at 0,0).
      // They belong where the text order puts them: right after prev.
      if (ink && (c.right <= c.left || c.top <= c.bottom)) {
        if (prev == null) continue;
        if (word == null) {
          word = _Word(PositionedChar(c.char, prev.right, prev.right, prev.top, prev.bottom));
          run.words.add(word);
        }
        word.text.write(c.char);
        continue;
      }
      if (!ink) {
        word = null;
        if (c.char == '\n' || c.char == '\r') {
          if (run.words.isNotEmpty) runs.add(run);
          run = _Run();
        }
        continue;
      }
      // The text order jumped (back left, or to another height): new run.
      if (prev != null && (c.left < prev.left - prev.height || (c.middle - prev.middle).abs() > prev.height)) {
        if (run.words.isNotEmpty) runs.add(run);
        run = _Run();
        word = null;
      }
      if (word == null) {
        word = _Word(c);
        run.words.add(word);
      }
      word.text.write(c.char);
      if (c.right > word.right) word.right = c.right;
      if (_alnum.hasMatch(c.char)) run.letters.add(c);
      prev = c;
    }
    if (run.words.isNotEmpty) runs.add(run);
    if (runs.isEmpty) continue;

    final widths = [
      for (final r in runs)
        for (final c in r.letters) c.right - c.left,
    ]..sort();
    final cell = widths.isEmpty ? 5.0 : widths[widths.length ~/ 2]; // one column

    // Rows, top of the page first.
    runs.sort((a, b) => b.middle.compareTo(a.middle));
    final rows = <List<_Run>>[];
    for (final r in runs) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null && (row.first.middle - r.middle).abs() < row.first.height * 0.5) {
        row.add(r);
      } else {
        rows.add([r]);
      }
    }

    for (final row in rows) {
      final words = _joinNumbers([for (final r in row) ...r.words]..sort((a, b) => a.left.compareTo(b.left)), cell);
      final line = StringBuffer();
      var col = 0;
      _Word? last;
      for (final w in words) {
        var target = (w.left / cell).round();
        // Words close together are one phrase: a single space. Wider gaps keep
        // their place so the amount columns stay to the right.
        if (last != null && (w.left - last.right) < cell * 2) target = col + 1;
        if (last != null && target <= col) target = col + 1;
        line.write(' ' * (target - col).clamp(0, 1000));
        col = target < col ? col : target;
        line.write(w.text);
        col += w.text.length;
        last = w;
      }
      out.writeln(line);
    }
  }
  return out.toString();
}

/// Text of a PDF file in layout form. [password] is asked for when the file
/// is encrypted; returning null gives up (pdfrx then throws PdfPasswordException).
Future<String> pdfLayoutText(String path, {Future<String?> Function()? password}) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path, passwordProvider: password);
  try {
    return layoutText(await documentChars(doc));
  } finally {
    await doc.dispose();
  }
}

/// Every page's characters with their positions.
Future<List<List<PositionedChar>>> documentChars(PdfDocument doc) async => [
      for (final page in doc.pages)
        if (await page.loadText() case final raw?)
          [
            for (var i = 0; i < raw.fullText.length && i < raw.charRects.length; i++)
              PositionedChar(raw.fullText[i], raw.charRects[i].left, raw.charRects[i].right,
                  raw.charRects[i].top, raw.charRects[i].bottom),
          ],
    ];

/// Account number as printed in a statement header, e.g. `XXXXXXXX4321` or
/// `110012344321`; null when the header has none.
String? statementAccount(String text) {
  final m = RegExp(r'(?:A/c|Account)\s*(?:No\.?|Number)?\s*[:\-]?\s*([X*\d]{6,})', caseSensitive: false)
      .firstMatch(text);
  return m?.group(1);
}
