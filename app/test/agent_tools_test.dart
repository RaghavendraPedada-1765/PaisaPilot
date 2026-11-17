import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/agent/agent_tools.dart';
import 'package:paisapilot/data/database.dart';

void main() {
  late AppDatabase db;
  late AgentTools tools;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tools = AgentTools(db);
    final canara = await db.into(db.accounts).insert(AccountsCompanion.insert(name: 'Canara XX4321', kind: 'bank'));
    final cats = {for (final c in await db.select(db.categories).get()) c.name: c.id};
    Future<int> payee(String name) => db.into(db.payees).insert(PayeesCompanion.insert(rawName: name));
    final swiggy = await payee('SWIGGY'), zudio = await payee('ZUDIO'), me = await payee('RAVI KUMAR');
    final mom = await payee('MOM');
    for (final (date, time, dir, amount, p, cat) in [
      ('2026-10-03', '13:05:09', 'DR', 250.0, swiggy, cats['Food and cafes']),
      ('2026-10-15', null, 'DR', 1250.5, swiggy, cats['Food and cafes']),
      ('2026-10-20', '19:00:00', 'DR', 2999.0, zudio, cats['Shopping']),
      ('2026-10-21', null, 'DR', 5000.0, me, cats['Self transfer']), // not spending
      ('2026-10-25', null, 'DR', 400.0, mom, null), // unsorted
      ('2026-10-28', null, 'CR', 10000.0, mom, null),
      ('2026-11-02', null, 'DR', 99.0, swiggy, cats['Food and cafes']),
    ]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
          accountId: canara, txnDate: date, txnTime: Value(time), direction: dir, amount: amount, source: 'manual',
          payeeId: Value(p), categoryId: Value(cat)));
    }
  });
  tearDown(() => db.close());

  const october = {'from': '2026-10-01', 'to': '2026-10-31'};

  test('spending by category leaves out self transfers and keeps unsorted', () async {
    final r = await tools.run('spending_summary', october);
    expect((r['total'], r['payments']), (4899.5, 4));
    expect(r['by_category'], [
      {'name': 'Shopping', 'amount': 2999, 'payments': 1},
      {'name': 'Food and cafes', 'amount': 1500.5, 'payments': 2},
      {'name': 'Unsorted', 'amount': 400, 'payments': 1},
    ]);
  });

  test('one category, money received, and grouping by payee or month', () async {
    expect((await tools.run('spending_summary', {...october, 'category': 'food and cafes'}))['total'], 1500.5);
    expect((await tools.run('spending_summary', {...october, 'category': 'Unsorted'}))['total'], 400);
    expect((await tools.run('spending_summary', {...october, 'direction': 'received'}))['total'], 10000);
    final byPayee = await tools.run('spending_summary', {...october, 'group_by': 'payee'});
    expect((byPayee['by_payee'] as List).first, {'name': 'ZUDIO', 'amount': 2999, 'payments': 1});
    final byMonth = await tools.run('spending_summary', {'group_by': 'month'});
    expect(byMonth['by_month'], [
      {'name': '2026-10', 'amount': 4899.5, 'payments': 4},
      {'name': '2026-11', 'amount': 99, 'payments': 1},
    ]);
  });

  test('listing transactions: filters, largest first, limit, time', () async {
    final r = await tools.run('list_transactions', {...october, 'sort': 'largest', 'limit': 2});
    expect(r['transactions'], [
      {'date': '2026-10-21', 'payee': 'RAVI KUMAR', 'amount': 5000, 'category': 'Self transfer', 'account': 'Canara XX4321'},
      {'date': '2026-10-20', 'time': '19:00', 'payee': 'ZUDIO', 'amount': 2999, 'category': 'Shopping', 'account': 'Canara XX4321'},
    ]);
    final small = await tools.run('list_transactions', {'payee': 'swig', 'max_amount': 300});
    expect([for (final t in small['transactions'] as List) t['amount']], [99, 250]);
  });

  test('payee history', () async {
    final r = await tools.run('payee_history', {'payee': 'mom'});
    expect((r['payments'], r['total_paid'], r['total_received'], r['usual_category']), (2, 400, 10000, 'Unsorted'));
    expect((r['first_date'], r['last_date']), ('2026-10-25', '2026-10-28'));
    expect((await tools.run('payee_history', {'payee': 'nobody'}))['error'], contains('no payee'));
  });

  test('bad arguments come back as errors the model can read, never exceptions', () async {
    expect((await tools.run('spending_summary', {'from': 'last month'}))['error'], contains('date'));
    expect((await tools.run('spending_summary', {'group_by': 'weekday'}))['error'], contains('group_by'));
    expect((await tools.run('list_transactions', {'min_amount': 'lots'}))['error'], contains('number'));
    expect((await tools.run('make_coffee', {}))['error'], contains('unknown tool'));
  });

  test('every tool the model is offered can run', () async {
    for (final t in AgentTools.tools) {
      final args = t.name == 'payee_history' ? {'payee': 'swiggy'} : <String, Object?>{};
      expect((await tools.run(t.name, args)).containsKey('error'), isFalse, reason: t.name);
    }
  });
}
