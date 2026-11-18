import 'package:drift/drift.dart';

import '../data/database.dart';
import 'categorizer.dart';
import 'sms_parser.dart';
import 'statement_parser.dart';

enum _Outcome { added, named, known }

class StatementImport {
  const StatementImport(this.result, {required this.inserted, required this.named, required this.inApp});
  final StatementResult result;
  final int inserted; // rows not already in the database
  final int named; // balance-only SMS rows that got the statement's payee
  int get duplicates => result.rows.length - inserted;

  /// The account's rows in PaisaPilot over the statement's dates, after the
  /// import. Equal to the statement's count when nothing is missing or doubled.
  final int inApp;
  bool get reconciles => inApp == result.rows.length;
  String? get firstDate => _span(result.rows)?.$1;
  String? get lastDate => _span(result.rows)?.$2;
}

/// Earliest and latest ISO dates of [rows].
(String, String)? _span(List<StatementRow> rows) {
  if (rows.isEmpty) return null;
  final dates = [for (final r in rows) r.date]..sort();
  return (dates.first, dates.last);
}

class SmsImport {
  const SmsImport(this.sms, this.inserted);
  final SmsTxn sms;
  final bool inserted; // false when the payment was already recorded
}

/// Writes parsed statements and SMS alerts into the database. Rows that share
/// an account, UPI ref and direction with an existing row are skipped, so the
/// same payment arriving by SMS and by statement is stored once.
class Importer {
  Importer(this.db);
  final AppDatabase db;

  static const _bankNames = {
    'canara': 'Canara',
    'icici': 'ICICI',
    'slice': 'slice',
    'slicebank': 'slice bank',
    'cgg': 'CGG Bank',
    'fampay': 'FamPay',
  };

  Future<StatementImport> importStatement(int accountId, String layoutText) {
    final result = parseStatement(layoutText);
    return db.transaction(() async {
      var inserted = 0, named = 0;
      for (final r in result.rows) {
        final (name, vpa) = party(r.desc);
        final outcome = await _insert(
          accountId: accountId,
          date: r.date,
          time: r.time,
          direction: r.direction,
          amount: r.amount,
          balance: r.balance,
          payeeName: name,
          vpa: vpa,
          upiRef: r.upiRef,
          source: 'statement',
          rawText: r.desc,
        );
        if (outcome == _Outcome.added) inserted++;
        if (outcome == _Outcome.named) named++;
      }
      var inApp = 0;
      if (_span(result.rows) case (final from, final to)) {
        final t = db.transactions;
        final count = t.id.count();
        inApp = await (db.selectOnly(t)
              ..addColumns([count])
              ..where(t.accountId.equals(accountId) & t.txnDate.isBetweenValues(from, to)))
            .map((row) => row.read(count)!)
            .getSingle();
      }
      return StatementImport(result, inserted: inserted, named: named, inApp: inApp);
    });
  }

  /// Returns null for non-transaction messages. The account is matched on its
  /// last digits and created if new.
  Future<SmsImport?> importSms(String body, {DateTime? receivedAt}) async {
    final sms = parseSms(body);
    if (sms == null) return null;
    final date = sms.date ?? (receivedAt ?? DateTime.now()).toIso8601String().substring(0, 10);
    // Most alerts carry no time, but they arrive within seconds of the
    // payment: use the arrival time when it is the same day.
    String? time = sms.time;
    if (time == null && receivedAt != null && receivedAt.toIso8601String().startsWith(date)) {
      time = receivedAt.toIso8601String().substring(11, 19);
    }
    final outcome = await db.transaction(() async {
      final accountId = await _accountFor(sms);
      return _insert(
        accountId: accountId,
        date: date,
        time: time,
        direction: sms.direction,
        amount: sms.amount,
        balance: sms.balance,
        payeeName: sms.party,
        vpa: '',
        upiRef: sms.ref,
        source: 'sms',
        rawText: body,
      );
    });
    return SmsImport(sms, outcome == _Outcome.added);
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Same bank and the same trailing digits: alerts mask one account as both
  /// XXX321 and XX4321. Alerts without a number (wallets, slice card
  /// repayments) match the bank's account of the same kind.
  Future<int> _accountFor(SmsTxn sms) async {
    final bank = _bankNames[sms.source] ?? sms.source;
    final digits = _digits(sms.account);
    final kind = sms.source == 'slice' ? 'credit_card' : (digits.isEmpty ? 'wallet' : 'bank');
    for (final a in await db.select(db.accounts).get()) {
      if (!a.name.toLowerCase().startsWith(bank.toLowerCase())) continue;
      final d = _digits(a.maskedNumber ?? '');
      if (digits.isEmpty) {
        if (a.kind == kind) return a.id;
        continue;
      }
      if (d == digits) return a.id;
      if (d.length >= 3 && digits.length >= 3 && (d.endsWith(digits) || digits.endsWith(d))) return a.id;
    }
    return db.into(db.accounts).insert(AccountsCompanion.insert(
      name: digits.isNotEmpty ? '$bank ${sms.account}' : (kind == 'credit_card' ? '$bank card' : bank),
      kind: kind,
      maskedNumber: Value(digits.isEmpty ? null : sms.account),
    ));
  }

  Future<Payee?> _payee(String name, String vpa) async {
    if (name.isEmpty) return null; // balance-only alerts name no one
    final v = vpa.isEmpty ? null : vpa;
    final existing = await (db.select(db.payees)
          ..where((p) => p.rawName.equals(name) & p.vpa.equalsNullable(v)))
        .getSingleOrNull();
    if (existing != null) return existing;
    return db.into(db.payees).insertReturning(PayeesCompanion.insert(rawName: name, vpa: Value(v)));
  }

  Future<int> _categoryId(String name) async {
    final c = await (db.select(db.categories)..where((c) => c.name.equals(name))).getSingleOrNull();
    return c?.id ?? await db.into(db.categories).insert(CategoriesCompanion.insert(name: name));
  }

  Future<_Outcome> _insert({
    required int accountId,
    required String date,
    String? time,
    required String direction,
    required double amount,
    double? balance,
    required String payeeName,
    required String vpa,
    String? upiRef,
    required String source,
    required String rawText,
  }) async {
    final t = db.transactions;
    Expression<bool> sameMoney(Transactions x) =>
        x.accountId.equals(accountId) &
        x.txnDate.equals(date) &
        x.direction.equals(direction) &
        x.amount.equals(amount);

    // The payment is already stored as [row]: fill in what it lacks (its time,
    // and for a UPI row its balance) and report it as known.
    Future<_Outcome> known(Txn row) async {
      final fillTime = row.txnTime == null && time != null;
      final fillBalance = row.balanceAfter == null && balance != null && row.upiRef != null && upiRef == null;
      if (fillTime || fillBalance) {
        await (db.update(t)..where((x) => x.id.equals(row.id))).write(TransactionsCompanion(
          txnTime: fillTime ? Value(time) : const Value.absent(),
          balanceAfter: fillBalance ? Value(balance) : const Value.absent(),
        ));
      }
      return _Outcome.known;
    }

    if (upiRef == null) {
      // UNIQUE (account_id, upi_ref, direction) never fires for a NULL ref,
      // so repeats are recognised here.
      final candidates = await (db.select(t)..where(sameMoney)).get();
      final sameBalance = balance == null
          ? null
          : candidates
              .where((c) => c.balanceAfter != null && (c.balanceAfter!.abs() - balance.abs()).abs() < 0.005)
              .firstOrNull;
      final match = sameBalance ?? candidates.where((c) => c.rawText == rawText).firstOrNull;
      if (match != null) return known(match);
      // A statement is complete for its dates: an alert without a ref that
      // matches one of its ref-less rows is that row, whatever balance it shows.
      if (source == 'sms') {
        final stmt = candidates.where((c) => c.source == 'statement' && c.upiRef == null).firstOrNull;
        if (stmt != null) return known(stmt);
      }
      // No ref and no balance (card spends): the same alert by SMS and by
      // email differs in wording, so match on the payee instead.
      if (balance == null && payeeName.isNotEmpty) {
        final payees = await (db.select(db.payees)..where((p) => p.rawName.equals(payeeName))).get();
        final same = candidates.where((c) => payees.any((p) => p.id == c.payeeId)).firstOrNull;
        if (same != null) return known(same);
      }
      // Canara often sends a balance-only alert next to the UPI alert for the
      // same payment: give the UPI row its balance instead of adding a row.
      final twin = candidates.where((c) => c.upiRef != null && c.balanceAfter == null).firstOrNull;
      if (twin != null) return known(twin);
    } else {
      final existing = await (db.select(t)
            ..where((x) =>
                x.accountId.equals(accountId) & x.upiRef.equals(upiRef) & x.direction.equals(direction))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) return known(existing);
    }

    final payee = await _payee(payeeName, vpa);
    int? categoryId = payee?.defaultCategoryId;
    // Following the payee's default is not an individual label: 'rule', so
    // a later change to the payee reaches this row too.
    String? categorySource = categoryId == null ? null : 'rule';
    if (categoryId == null && payeeName.isNotEmpty) {
      final rule = categorise(payeeName, vpa, direction);
      if (rule != null) {
        categoryId = await _categoryId(rule);
        categorySource = 'rule';
      }
    }

    if (upiRef == null && source == 'statement') {
      // A statement row without a ref (charges, interest) takes over the SMS
      // alert for it even when balances differ: the SMS shows the balance when
      // it was sent, the statement its running balance. The row becomes a
      // statement row, so each SMS alert is claimed once and two identical
      // charges on one day stay two rows.
      final sms = await (db.select(t)
            ..where((x) => sameMoney(x) & x.upiRef.isNull() & x.source.equals('sms'))
            ..limit(1))
          .getSingleOrNull();
      if (sms != null) {
        await (db.update(t)..where((x) => x.id.equals(sms.id))).write(TransactionsCompanion(
          source: const Value('statement'),
          payeeId: Value(payee?.id ?? sms.payeeId),
          txnTime: Value(time ?? sms.txnTime),
          balanceAfter: Value(balance),
          categoryId: sms.categorySource == 'user' ? const Value.absent() : Value(categoryId),
          categorySource: sms.categorySource == 'user' ? const Value.absent() : Value(categorySource),
          rawText: Value(rawText),
        ));
        return _Outcome.named;
      }
    }

    if (upiRef != null) {
      // The other order: the balance-only alert came first. Upgrade that row
      // with the ref, payee and time rather than adding a second one.
      final orphan = await (db.select(t)
            ..where((x) => sameMoney(x) & x.upiRef.isNull() & x.source.equals('sms') & x.payeeId.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (orphan != null) {
        await (db.update(t)..where((x) => x.id.equals(orphan.id))).write(TransactionsCompanion(
          upiRef: Value(upiRef),
          payeeId: Value(payee?.id),
          txnTime: Value(time ?? orphan.txnTime),
          balanceAfter: Value(orphan.balanceAfter ?? balance),
          categoryId: orphan.categorySource == 'user' ? const Value.absent() : Value(categoryId),
          categorySource: orphan.categorySource == 'user' ? const Value.absent() : Value(categorySource),
          rawText: Value(rawText),
        ));
        return _Outcome.named; // payee filled in
      }
    }

    final row = await db.into(db.transactions).insertReturningOrNull(
          TransactionsCompanion.insert(
            accountId: accountId,
            txnDate: date,
            txnTime: Value(time),
            direction: direction,
            amount: amount,
            balanceAfter: Value(balance),
            payeeId: Value(payee?.id),
            categoryId: Value(categoryId),
            categorySource: Value(categorySource),
            upiRef: Value(upiRef),
            source: source,
            rawText: Value(rawText),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return row != null ? _Outcome.added : _Outcome.known;
  }
}
