import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/import/statement_parser.dart';

import 'statement_fixture.dart';

void main() {
  final result = parseStatement(statementFixture);

  test('every row reconciles to the running balance', () {
    expect(result.opening, 1000.0);
    expect(result.bad, isEmpty);
    expect(result.rows, hasLength(4));
    expect(result.mismatches, 0);
    expect(result.closing, -495.0);
  });

  test('rows carry date, direction, amount and signed balance', () {
    final r = result.rows;
    expect([for (final x in r) x.date], ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']);
    expect([for (final x in r) x.direction], ['CR', 'DR', 'DR', 'CR']);
    expect([for (final x in r) x.amount], [500.0, 1700.0, 300.0, 5.0]);
    expect([for (final x in r) x.balance], [1500.0, -200.0, -500.0, -495.0]);
  });

  test('opening balance on the next line, spaced labels and "Chq :"', () {
    final text = statementFixture
        .replaceFirst(RegExp(r'Opening Balance\s+1,000\.00'), 'Opening  Balance\n${' ' * 70}1,000.00')
        .replaceAll('Chq: ', 'Chq : 123');
    final r = parseStatement(text);
    expect((r.opening, r.rows.length, r.mismatches), (1000.0, 4, 0));
  });

  test('a statement without an opening balance yields nothing instead of failing', () {
    final r = parseStatement('Date Particulars\n01-10-2026  UPI/CR/1/A   500.00   1,500.00\nChq:');
    expect(r.opening, isNull);
    expect(r.rows, isEmpty);
  });

  test('description is joined across lines', () {
    final r = result.rows.first;
    expect(r.desc, 'UPI/CR/111111111111/ALICE/SBIN/alice@okaxis/Payment//ref1/01/10/202610:15:00');
    expect(r.upiRef, '111111111111');
    expect(r.time, '10:15:00');
    expect(result.rows.last.upiRef, isNull);
  });
}
