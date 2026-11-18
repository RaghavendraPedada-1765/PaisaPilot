import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../import/categorizer.dart';

part 'database.g.dart';

typedef UnsortedPayee = ({int id, String name, int payments, double spent});

@DriftDatabase(include: {'schema.drift', 'queries.drift'})
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database. Tests pass an in-memory executor.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'paisapilot'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final name in categoryNames) {
            await into(categories).insert(CategoriesCompanion.insert(
              name: name,
              countsAsSpend: Value(!nonSpendCategories.contains(name)),
            ));
          }
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(settings);
          if (from < 3) {
            await m.createTable(attachments);
            await m.createIndex(idxAttachmentTxn);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<String?> getSetting(String name) async =>
      (await (select(settings)..where((s) => s.name.equals(name))).getSingleOrNull())?.value;

  Future<void> setSetting(String name, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(name: name, value: value));

  /// Deletes a transaction and its attachment rows; returns the photo file
  /// names so the caller can remove the files.
  Future<List<String>> deleteTxn(int id) => transaction(() async {
        final photos = await (select(attachments)..where((a) => a.txnId.equals(id))).get();
        await (delete(attachments)..where((a) => a.txnId.equals(id))).go();
        await (delete(transactions)..where((t) => t.id.equals(id))).go();
        return [for (final p in photos) p.fileName];
      });

  Stream<List<Attachment>> watchAttachments(int txnId) =>
      (select(attachments)..where((a) => a.txnId.equals(txnId))..orderBy([(a) => OrderingTerm.asc(a.id)]))
          .watch();

  Future<int> addAttachment(int txnId, String fileName) => into(attachments).insert(
      AttachmentsCompanion.insert(txnId: txnId, fileName: fileName, addedAt: DateTime.now().toIso8601String()));

  Future<void> deleteAttachment(int id) => (delete(attachments)..where((a) => a.id.equals(id))).go();

  Stream<List<Category>> watchCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  /// User labels a transaction (null = unsorted). With [forPayee], the payee
  /// remembers the category and its other rows follow, except ones the user
  /// labelled individually.
  ///
  /// Only the tapped row becomes a 'user' label; rows that follow the payee
  /// get 'rule', so a later change to the payee reaches them again.
  Future<void> setCategory(Txn txn, int? categoryId, {bool forPayee = false}) {
    return transaction(() async {
      await (update(transactions)..where((t) => t.id.equals(txn.id))).write(TransactionsCompanion(
        categoryId: Value(categoryId),
        categorySource: Value(categoryId == null ? null : 'user'),
      ));
      final payeeId = txn.payeeId;
      if (!forPayee || payeeId == null) return;
      final follows = await _followsPayee(payeeId);
      await (update(payees)..where((p) => p.id.equals(payeeId)))
          .write(PayeesCompanion(defaultCategoryId: Value(categoryId)));
      await (update(transactions)..where((t) => t.id.equals(txn.id).not() & follows(t))).write(TransactionsCompanion(
        categoryId: Value(categoryId),
        categorySource: Value(categoryId == null ? null : 'rule'),
      ));
    });
  }

  /// How many rows `setCategory(txn, _, forPayee: true)` would change,
  /// including [txn] itself.
  Future<int> payeeChangeCount(Txn txn) async {
    final payeeId = txn.payeeId;
    if (payeeId == null) return 1;
    final follows = await _followsPayee(payeeId);
    final others = transactions.id.count();
    final query = selectOnly(transactions)
      ..addColumns([others])
      ..where(transactions.id.equals(txn.id).not() & follows(transactions));
    return 1 + (await query.map((r) => r.read(others)!).getSingle());
  }

  /// The payee's rows that follow its category: everything not labelled
  /// individually. Older versions marked rows that followed the payee as
  /// 'user' too, so rows still matching the payee's default count as
  /// following it.
  Future<Expression<bool> Function(Transactions)> _followsPayee(int payeeId) async {
    final payee = await (select(payees)..where((p) => p.id.equals(payeeId))).getSingle();
    final current = payee.defaultCategoryId;
    return (Transactions t) =>
        t.payeeId.equals(payeeId) &
        (t.categorySource.isNull() |
            t.categorySource.isNotValue('user') |
            (current == null ? const Constant(false) : t.categoryId.equals(current)));
  }

  /// Payees with unsorted spending (all months), largest total first.
  Stream<List<UnsortedPayee>> watchUnsortedPayees() => customSelect(
        '''SELECT p.id, COALESCE(p.display_name, p.raw_name) AS name,
             COUNT(*) AS payments, SUM(t.amount) AS spent
           FROM transactions t JOIN payees p ON p.id = t.payee_id
           WHERE t.category_id IS NULL AND t.direction = 'DR'
           GROUP BY p.id ORDER BY spent DESC, name, p.id''',
        readsFrom: {transactions, payees},
      )
          .map((r) => (
                id: r.read<int>('id'),
                name: r.read<String>('name'),
                payments: r.read<int>('payments'),
                spent: r.read<double>('spent'),
              ))
          .watch();

  /// The payee's unsorted payments, as reviewed before labelling them.
  Future<List<int>> unsortedPaymentIds(int payeeId) => (selectOnly(transactions)
        ..addColumns([transactions.id])
        ..where(transactions.payeeId.equals(payeeId) &
            transactions.categoryId.isNull() &
            transactions.direction.equals('DR')))
      .map((r) => r.read(transactions.id)!)
      .get();

  /// Labels the reviewed payments [txnIds] (those still unsorted, so a
  /// correction made meanwhile stays) and makes [categoryId] the payee's
  /// default. The rows follow the payee ('rule'), so changing the payee
  /// later moves them too. Rows the payee already had labelled are kept.
  Future<void> labelPayee(int payeeId, int categoryId, List<int> txnIds) => transaction(() async {
        await (update(transactions)..where((t) => t.id.isIn(txnIds) & t.categoryId.isNull())).write(
            TransactionsCompanion(categoryId: Value(categoryId), categorySource: const Value('rule')));
        await (update(payees)..where((p) => p.id.equals(payeeId)))
            .write(PayeesCompanion(defaultCategoryId: Value(categoryId)));
      });
}
