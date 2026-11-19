import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/data/photo_store.dart';

void main() {
  late AppDatabase db;
  late int account, food, shopping;
  late Map<String, int> ids;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    account = await db.into(db.accounts).insert(AccountsCompanion.insert(name: 'Canara', kind: 'bank'));
    final cats = {for (final c in await db.select(db.categories).get()) c.name: c.id};
    food = cats['Food and cafes']!;
    shopping = cats['Shopping']!;
    ids = {};
    for (final (name, date, amount, category) in [
      ('tea', '2026-11-03', 20.0, food),
      ('shoes', '2026-11-01', 2500.0, shopping),
      ('lunch', '2026-11-02', 180.0, food),
      ('mystery', '2026-11-04', 900.0, null),
    ]) {
      ids[name] = await db.into(db.transactions).insert(TransactionsCompanion.insert(
          accountId: account, txnDate: date, direction: 'DR', amount: amount, source: 'manual',
          categoryId: Value(category), rawText: Value(name)));
    }
  });
  tearDown(() => db.close());

  Future<List<String?>> names({int? category, bool byAmount = false}) async =>
      [for (final r in await db.activity(null, category, null, '', byAmount, 100).get()) r.t.rawText];

  test('newest first by default, largest first on request', () async {
    expect(await names(), ['mystery', 'tea', 'lunch', 'shoes']);
    expect(await names(byAmount: true), ['shoes', 'mystery', 'lunch', 'tea']);
  });

  test('category tabs: one category, or unsorted only', () async {
    expect(await names(category: food), ['tea', 'lunch']);
    expect(await names(category: food, byAmount: true), ['lunch', 'tea']);
    expect(await names(category: 0), ['mystery']);
  });

  test('rows report how many photos they have', () async {
    await db.addAttachment(ids['tea']!, 'a.jpg');
    await db.addAttachment(ids['tea']!, 'b.jpg');
    final rows = {for (final r in await db.activity(null, null, null, '', false, 100).get()) r.t.rawText: r.photos};
    expect((rows['tea'], rows['lunch']), (2, 0));
  });

  test('deleting a transaction removes its photos and returns their files', () async {
    await db.addAttachment(ids['tea']!, 'a.jpg');
    await db.addAttachment(ids['lunch']!, 'keep.jpg');
    expect(await db.deleteTxn(ids['tea']!), ['a.jpg']);
    final left = await db.select(db.attachments).get();
    expect([for (final a in left) a.fileName], ['keep.jpg']);
  });

  test('photo store copies files in and removes them', () async {
    final tmp = await Directory.systemTemp.createTemp('pp_photos');
    addTearDown(() => tmp.delete(recursive: true));
    final src = File('${tmp.path}/camera_shot.png')..writeAsBytesSync([1, 2, 3]);
    final store = PhotoStore(() async => tmp);
    final name = await store.save(src.path);
    expect(name, endsWith('.png'));
    final kept = await store.file(name);
    expect(kept.readAsBytesSync(), [1, 2, 3]);
    await store.remove(name);
    expect(kept.existsSync(), isFalse);
  });

  test('a version 2 database gains the attachments table', () async {
    final old = AppDatabase(NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA user_version = 2')));
    final tables = await old.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    expect([for (final t in tables) t.read<String>('name')], contains('attachments'));
    await old.close();
  });

  group('month filter and totals', () {
    Future<void> add(String date, String direction, double amount, int? category) => db
        .into(db.transactions)
        .insert(TransactionsCompanion.insert(
            accountId: account, txnDate: date, direction: direction, amount: amount, source: 'manual',
            categoryId: Value(category)));

    setUp(() async {
      await add('2026-10-31', 'DR', 70, food); // October: outside November
      await add('2026-11-05', 'CR', 45, food); // a refund: money in, not spending
      await add('2026-12-01', 'DR', 10, food); // December
    });

    test('activity keeps to one month, including its last day', () async {
      final nov = await db.activity(null, food, '2026-11', '', false, 100).get();
      expect([for (final r in nov) r.t.amount], [45.0, 20.0, 180.0]);
      final oct = await db.activity(null, null, '2026-10', '', false, 100).get();
      expect([for (final r in oct) r.t.txnDate], ['2026-10-31']);
    });

    test('totals cover every matching row, beyond the row limit', () async {
      final shown = await db.activity(null, null, null, '', false, 2).get();
      final t = await db.activityTotals(null, null, null, '').getSingle();
      expect(shown.length, 2);
      expect((t.n, t.outTotal, t.inTotal), (7, 20 + 2500 + 180 + 900 + 70 + 10.0, 45.0));
    });

    test('a donut slice equals Activity filtered to that category and month', () async {
      final slices = await db.spendByCategory('2026-11').get();
      for (final s in slices) {
        final t = await db.activityTotals('DR', s.categoryId ?? 0, '2026-11', '').getSingle();
        final rows = await db.activity('DR', s.categoryId ?? 0, '2026-11', '', false, 500).get();
        expect(t.outTotal, s.total, reason: s.category ?? 'Unsorted');
        expect(rows.fold<double>(0, (sum, r) => sum + r.t.amount), s.total);
        expect(rows.length, s.txnCount);
      }
      expect([for (final s in slices) (s.category, s.total)],
          [('Shopping', 2500.0), (null, 900.0), ('Food and cafes', 200.0)]);
    });

    test('period totals tell an empty period from a zero spend', () async {
      final empty = await db.periodTotals('2026-09-01', '2026-09-30').getSingle();
      expect((empty.spent, empty.txns), (0.0, 0));
      await add('2026-09-10', 'CR', 500, null);
      final onlyIncome = await db.periodTotals('2026-09-01', '2026-09-30').getSingle();
      expect((onlyIncome.spent, onlyIncome.received, onlyIncome.txns), (0.0, 500.0, 1));
    });

    test('months with transactions, newest first', () async {
      expect(await db.activityMonths().get(), ['2026-12', '2026-11', '2026-10']);
    });
  });
}
